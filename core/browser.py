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


def find_system_chromium():
    """在常见路径里找系统安装的 chromium 可执行文件"""
    for path in SYSTEM_CHROMIUM_CANDIDATES:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    # PATH 里找
    for name in ["chromium-browser", "chromium", "google-chrome"]:
        found = shutil.which(name)
        if found:
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
    if env == Environment.LOCAL:
        os.environ["PLAYWRIGHT_BROWSERS_PATH"] = os.path.abspath(
            os.path.join(os.path.dirname(__file__), PLAYWRIGHT_BROWSERS_PATH)
        )
        if DEBUG:
            headless = False
    elif env == Environment.PACKED:
        os.environ["PLAYWRIGHT_BROWSERS_PATH"] = os.path.abspath(
            os.path.join(os.path.dirname(sys.executable), PLAYWRIGHT_BROWSERS_PATH)
        )

    # 优先用系统 chromium（arm64 等无 Playwright 预编译浏览器的环境）
    system_chromium = find_system_chromium()
    launch_kwargs = {"headless": headless}
    if system_chromium:
        launch_kwargs["executable_path"] = system_chromium
        print(f"[browser] 使用系统 chromium: {system_chromium}")
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
