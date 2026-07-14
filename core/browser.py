import os, sys
import shutil
import subprocess
import traceback
from playwright.sync_api import sync_playwright
from utils.config import DEBUG, get_environment, Environment

PLAYWRIGHT_BROWSERS_PATH = "../chrome"

# arm64/无网络环境下优先用系统 chromium
SYSTEM_CHROMIUM_CANDIDATES = [
    # snap chromium 真实二进制（绕过 snap confinement 的 cgroup 问题）
    "/snap/chromium/current/usr/lib/chromium-browser/chrome",
    "/usr/bin/chromium-browser",
    "/usr/bin/chromium",
    "/usr/bin/google-chrome",
    "/snap/bin/chromium",
]


def _is_wrapper_script(path):
    """判断一个文件是不是 wrapper 脚本（非真实 ELF 二进制）。
    Ubuntu 的 /usr/bin/chromium-browser 在没装 snap 时是个 shell 脚本，
    会直接报错退出，不能用。"""
    if not path or not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
        # ELF 二进制以 \x7fELF 开头；脚本以 #! 开头
        if magic == b"\x7fELF":
            return False  # 真实二进制
        return True  # 其他都当脚本处理
    except Exception:
        return False


def find_system_chromium():
    """在常见路径里找系统安装的 chromium 可执行文件"""
    for path in SYSTEM_CHROMIUM_CANDIDATES:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            if _is_wrapper_script(path):
                # 是 wrapper 脚本（如 Ubuntu 的 chromium-browser），
                # 跳过，用 Playwright 自带的更可靠
                continue
            return path
    # PATH 里找（也要跳过 wrapper 脚本）
    for name in ["chromium-browser", "chromium", "google-chrome"]:
        found = shutil.which(name)
        if found and not _is_wrapper_script(found):
            return found
    # 扫 snap 版本目录（current 可能不存在，找具体版本号目录）
    import glob
    for pattern in [
        "/snap/chromium/*/usr/lib/chromium-browser/chrome",
    ]:
        matches = sorted(glob.glob(pattern), reverse=True)
        if matches:
            return matches[0]
    return None


def install_browser():
    """
    安装 Chromium 浏览器
    """
    try:
        subprocess.run(["playwright", "install", "chromium"], check=True)
        print("浏览器安装完成，请重新运行程序。")
    except subprocess.CalledProcessError as e:
        print(f"发生未知错误：{e}")


def get_browser():
    """
    启动浏览器实例
    :return: 浏览器实例
    """

    headless = True

    env = get_environment()
    # 注意：不再强制设置 PLAYWRIGHT_BROWSERS_PATH。
    # arm64 环境下，设了这个变量会导致 Playwright 下载/查找完整版 chromium
    # （需要 X server），而不是 headless_shell。用默认缓存路径更可靠。
    if env == Environment.LOCAL:
        if DEBUG:
            headless = False

    # 优先用系统 chromium（arm64 等无 Playwright 预编译浏览器的环境）
    system_chromium = find_system_chromium()
    launch_kwargs = {"headless": headless}
    if system_chromium:
        launch_kwargs["executable_path"] = system_chromium
        print(f"[browser] 使用系统 chromium: {system_chromium}")
    else:
        # arm64 无 X server 环境下，必须显式指定 headless_shell 二进制，
        # 否则 Playwright 可能用完整版 chromium（需要 X server）
        import glob
        headless_shell = None
        for pattern in [
            os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell"),
            os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell"),
        ]:
            matches = sorted(glob.glob(pattern), reverse=True)
            if matches:
                headless_shell = matches[0]
                break
        if headless_shell:
            launch_kwargs["executable_path"] = headless_shell
            print(f"[browser] 使用 Playwright headless_shell: {headless_shell}")
        else:
            print("[browser] 使用 Playwright 自带 chromium")

    # arm64 / 受限内核环境下必须加这些参数，否则 chromium 启动崩溃
    # 注意：--single-process 在 arm64 上反而会崩，不用
    is_arm64 = os.uname().machine in ("aarch64", "arm64")
    if is_arm64 or system_chromium:
        launch_kwargs["args"] = [
            "--no-sandbox",
            "--disable-setuid-sandbox",
            "--disable-dev-shm-usage",
            "--disable-gpu",
            "--disable-software-rasterizer",
            "--no-zygote",
            "--disable-features=VizDisplayCompositor,UseChromeOSDirectVideoDecoder",
        ]

    try:
        # 启动浏览器
        playwright = sync_playwright().start()
        browser = playwright.chromium.launch(**launch_kwargs)
        return playwright, browser
    except Exception as e:
        # 捕获浏览器启动错误
        if "Executable doesn't exist" in str(e) and env != Environment.GITHUBACTION:
            print("浏览器可执行文件不存在！")
            install_browser()
            sys.exit(1)
        else:
            traceback.print_exc()
            raise  # 必须重新抛出，避免返回 None 导致调用方解包失败
