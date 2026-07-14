#!/bin/bash
# DouYinSparkFlow 原生部署脚本（适用于 Ubuntu/Debian arm64 及 x86_64）
# 不依赖 Docker，直接用系统 chromium + Python venv
set -e

echo "=========================================="
echo "  DouYinSparkFlow 原生部署脚本"
echo "=========================================="

# 检查是否 root，不是则用 sudo
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

echo ""
echo "[1/4] 安装系统依赖（chromium + Python venv）..."
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq \
    chromium-browser \
    python3 \
    python3-venv \
    python3-pip \
    >/dev/null 2>&1 || {
    # chromium-browser 包装不上时试 chromium
    echo "  chromium-browser 安装失败，尝试 chromium..."
    $SUDO apt-get install -y -qq chromium >/dev/null 2>&1 || {
        echo "  [错误] chromium 安装失败，请手动执行: sudo apt install chromium-browser"
        exit 1
    }
}

# 找 chromium 路径
CHROMIUM_PATH=""
for c in /usr/bin/chromium-browser /usr/bin/chromium /usr/bin/google-chrome; do
    if [ -x "$c" ]; then
        CHROMIUM_PATH="$c"
        break
    fi
done
if [ -z "$CHROMIUM_PATH" ]; then
    echo "  [警告] 未找到 chromium 可执行文件，请确认安装成功"
else
    echo "  chromium 路径: $CHROMIUM_PATH"
    $CHROMIUM_PATH --version 2>/dev/null || true
fi

echo ""
echo "[2/4] 创建 Python 虚拟环境..."
cd "$(dirname "$0")"
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate

echo ""
echo "[3/4] 安装 Python 依赖..."
pip install --upgrade pip -q
pip install -r requirements.txt -q

echo ""
echo "[4/4] 安装 Playwright 系统依赖（chromium 运行所需的库）..."
# 这一步只装系统库，不下载浏览器（我们用系统 chromium）
playwright install-deps chromium >/dev/null 2>&1 || {
    echo "  [提示] playwright install-deps 失败，但可能不影响（系统 chromium 自带依赖）"
}

echo ""
echo "=========================================="
echo "  部署完成！"
echo "=========================================="
echo ""
echo "使用方法："
echo "  1. 确认 .env 已创建（参考 .env.example）"
echo "  2. 立即运行一次："
echo "     cd $(pwd) && source venv/bin/activate && python main.py"
echo "  3. 设置定时任务（每天 9:00 运行）："
echo "     (crontab -l 2>/dev/null; echo '0 9 * * * cd $(pwd) && source venv/bin/activate && python main.py >> logs/cron.log 2>&1') | crontab -"
echo ""
