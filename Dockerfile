FROM python:3.11-slim

# 时区设为北京时间，定时任务按北京时间跑
ENV TZ=Asia/Shanghai
ENV PYTHONUNBUFFERED=1

# 安装 Playwright / chromium 运行所需的系统依赖
# fonts-liberation libnss3 libnspr4 libasound2 等是 chromium-headless 必需的
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates tzdata \
        fonts-liberation libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
        libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
        libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 \
        libatspi2.0-0 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 先装 Python 依赖（利用 Docker 层缓存）
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && playwright install chromium --with-deps --only-shell

# 复制项目代码（包含对 tasks.py / logger.py 的修复）
COPY . .

# logs 目录运行时会通过 volume 持久化，这里创建占位
RUN mkdir -p logs

# 入口脚本：立即跑一次 + 按 CRON_SCHEDULE 定时循环
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

# 默认每天北京时间 09:00 执行一次，可通过 -e CRON_SCHEDULE 覆盖
ENV CRON_SCHEDULE="0 9 * * *"
ENV RUN_NOW=1

CMD ["/app/run.sh"]
