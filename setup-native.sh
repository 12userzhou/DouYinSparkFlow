#!/bin/bash
# DouYinSparkFlow 原生部署脚本（适用于 Ubuntu/Debian arm64 及 x86_64）
# 使用 Playwright 自带 chromium，不依赖系统 chromium
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
echo "[1/5] 安装系统依赖（Python venv + Playwright 运行库）..."
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq \
    python3 \
    python3-venv \
    python3-pip \
    curl \
    libnspr4 \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    >/dev/null 2>&1 || {
    echo "  [警告] 部分系统依赖安装失败，可能需要手动补齐"
}

echo ""
echo "[2/5] 创建 Python 虚拟环境..."
cd "$(dirname "$0")"
# 部分 Ubuntu 22.04 系统的 venv 创建不完整（缺 activate/pip），用 --without-pip 兜底
rm -rf venv
python3 -m venv venv --without-pip
source venv/bin/activate
# 手动安装 pip
curl -sS https://bootstrap.pypa.io/get-pip.py | python3

echo ""
echo "[3/5] 安装 Python 依赖（使用阿里云镜像加速）..."
pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/

echo ""
echo "[4/5] 下载 Playwright chromium（使用官方 CDN）..."
# 国内环境用官方 azureedge CDN 最稳定，npmmirror 缺 arm64 headless_shell
PLAYWRIGHT_DOWNLOAD_HOST=https://playwright.azureedge.net playwright install chromium

echo ""
echo "[5/5] 创建日志目录..."
mkdir -p logs

echo ""
echo "=========================================="
echo "  部署完成！"
echo "=========================================="
echo ""
echo "下一步："
echo "  1. 创建 .env 配置文件（参考下方说明或 .env.example）"
echo "  2. 立即运行一次："
echo "     cd $(pwd) && source venv/bin/activate && python -u main.py"
echo "  3. 设置定时任务（每天 4:00 运行）："
echo "     (crontab -l 2>/dev/null | grep -v douyinsparkflow; echo '0 4 * * * cd $(pwd) && $(pwd)/venv/bin/python main.py >> $(pwd)/logs/cron.log 2>&1') | crontab -"
echo ""
echo "后续更新 cookie："
echo "  bash update_cookie.sh   # 交互式更新 .env 中的 cookie"
echo ""
