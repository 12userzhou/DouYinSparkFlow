#!/bin/bash
# DouYinSparkFlow Docker 一键部署脚本
# 在服务器上执行：bash deploy.sh
set -e

APP_DIR="$HOME/douyinsparkflow"
IMAGE_NAME="douyinsparkflow"
CONTAINER_NAME="douyinsparkflow"

echo "================ DouYinSparkFlow Docker 部署 ================"
echo ""

# 1. 检查 Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "[X] 未检测到 docker，请先安装："
    echo "    curl -fsSL https://get.docker.com | sh"
    echo "    systemctl enable --now docker"
    exit 1
fi
echo "[√] docker 已安装: $(docker --version)"

# 2. 检查内存（chromium 至少要 1.5GB）
MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
echo "[i] 当前内存: ${MEM_MB}MB"
if [ "$MEM_MB" -lt 1500 ]; then
    echo "[!] 内存不足 1.5GB，chromium 可能 OOM。建议加 swap："
    echo "    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"
    echo ""
    read -p "内存不足，仍要继续吗？(y/N): " ok
    [ "$ok" != "y" ] && exit 1
fi

# 3. 准备项目目录
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# 4. 如果代码不存在，从 GitHub 克隆（用你的 fork）
if [ ! -f "main.py" ]; then
    echo "[i] 克隆代码..."
    git clone https://github.com/12userzhou/DouYinSparkFlow.git .
fi
echo "[√] 代码就绪: $APP_DIR"

# 5. 检查 .env
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo ""
        echo "============================================================"
        echo "[!] 已生成 .env 文件，但里面是占位值！"
        echo "    请现在编辑 $APP_DIR/.env，把以下内容替换成你的真实配置："
        echo "      - TASKS         (任务列表 JSON)"
        echo "      - COOKIES_U1    (Cookie JSON，从浏览器导出)"
        echo "    参考: docs/配置生成器使用.md"
        echo "============================================================"
        echo ""
        read -p "编辑完 .env 后按回车继续构建..." _
    fi
fi
echo "[√] .env 已配置"

# 6. 构建镜像
echo "[i] 构建 docker 镜像（首次约 3~5 分钟，会下载 chromium）..."
docker build -t "$IMAGE_NAME" .
echo "[√] 镜像构建完成"

# 7. 停掉旧容器（如有）
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[i] 停止并删除旧容器..."
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

# 8. 运行容器
#    -d 后台运行
#    --restart unless-stopped  服务器重启后自动拉起
#    -v logs 持久化日志到宿主
#    --env-file .env 加载配置
#    CRON_SCHEDULE 默认每天北京时间 9:00，可改
echo "[i] 启动容器..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --env-file .env \
    -e CRON_SCHEDULE="0 9 * * *" \
    -e TZ=Asia/Shanghai \
    -v "$APP_DIR/logs:/app/logs" \
    "$IMAGE_NAME"

echo ""
echo "================ 部署完成 ================"
echo ""
echo "查看实时日志:"
echo "  docker logs -f $CONTAINER_NAME"
echo ""
echo "查看任务日志（文件）:"
echo "  ls $APP_DIR/logs/"
echo ""
echo "立即手动执行一次:"
echo "  docker exec $CONTAINER_NAME python main.py"
echo ""
echo "停止/重启:"
echo "  docker stop $CONTAINER_NAME"
echo "  docker restart $CONTAINER_NAME"
echo ""
echo "修改配置后重建:"
echo "  cd $APP_DIR && vim .env && docker rm -f $CONTAINER_NAME && docker run -d --name $CONTAINER_NAME --restart unless-stopped --env-file .env -e CRON_SCHEDULE='0 9 * * *' -e TZ=Asia/Shanghai -v $APP_DIR/logs:/app/logs $IMAGE_NAME"
