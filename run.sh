#!/bin/sh
# 容器入口：立即运行一次，然后按 CRON 表达式定时循环。
# 不依赖宿主 cron，纯 shell 实现，简化部署。
#
# 定时表达式通过环境变量 CRON_SCHEDULE 传入，默认每天北京时间 09:00。
# 例：CRON_SCHEDULE="0 9 * * *" 表示每天 9 点；"0 */6 * * *" 每 6 小时。

set -e

# 把 .env 里加载到环境（docker run 的 -e / --env-file 会覆盖）
if [ -f /app/.env ]; then
    set -a
    . /app/.env
    set +a
fi

# 立即执行一次（可选，通过 RUN_NOW=0 关闭）
RUN_NOW="${RUN_NOW:-1}"
if [ "$RUN_NOW" = "1" ]; then
    echo "[$(date '+%F %T')] 立即执行一次任务..."
    python main.py && echo "[$(date '+%F %T')] 本次任务完成" || echo "[$(date '+%F %T')] 本次任务失败(退出码 $?)"
fi

# 解析 cron 表达式 -> 秒级 sleep 间隔（简化版，支持以下几种常见写法）
# - "0 H * * *"        每天 H 点
# - "0 */N * * *"      每 N 小时
# - "*/M * * * *"      每 M 分钟
# 为简单可靠，这里用循环 + sleep 到下一个整点触发时刻的方式。
CRON_SCHEDULE="${CRON_SCHEDULE:-0 9 * * *}"

echo "[$(date '+%F %T')] 定时模式已启用，表达式: $CRON_SCHEDULE (容器时区: $(date +%Z))"

# 简化定时：把 5 段 cron 转成「下一次执行的延迟」。
# 支持常见场景：每天定点、每 N 小时、每 N 分钟。
next_delay() {
    # 读取当前时间
    NOW_EPOCH=$(date +%s)
    MIN=$(date +%-M)
    HOUR=$(date +%-H)
    DOM=$(date +%-d)
    MON=$(date +%-m)
    DOW=$(date +%-u)  # 1=Mon..7=Sun

    # 解析 cron 5 段
    set -- $CRON_SCHEDULE
    C_MIN=$1; C_HOUR=$2; C_DOM=$3; C_MON=$4; C_DOW=$5

    # 情况1: 每 N 分钟  */N * * * *
    case "$C_MIN" in
        */N|*/[0-9]*)
            N=${C_MIN#*/}
            echo $(( N * 60 ))
            return
            ;;
    esac

    # 情况2: 每 N 小时  0 */N * * *
    if [ "$C_MIN" = "0" ] && case "$C_HOUR" in */[0-9]*) true;; *) false;; esac; then
        N=${C_HOUR#*/}
        echo $(( N * 3600 ))
        return
    fi

    # 情况3: 每天定点  M H * * *
    if [ "$C_DOM" = "*" ] && [ "$C_MON" = "*" ] && [ "$C_DOW" = "*" ]; then
        # 计算今天还剩多少秒到 H:M，若已过则到明天
        TARGET_SEC=$(( ${C_HOUR#0} * 3600 + ${C_MIN#0} * 60 ))
        NOW_SEC=$(( HOUR * 3600 + MIN * 60 ))
        if [ "$TARGET_SEC" -gt "$NOW_SEC" ]; then
            echo $(( TARGET_SEC - NOW_SEC ))
        else
            echo $(( 86400 - NOW_SEC + TARGET_SEC ))
        fi
        return
    fi

    # 兜底：每 24 小时
    echo 86400
}

# 定时循环
while true; do
    DELAY=$(next_delay)
    echo "[$(date '+%F %T')] 下次执行在 ${DELAY} 秒后"
    # 分段 sleep，便于收到信号时退出
    REMAIN=$DELAY
    while [ "$REMAIN" -gt 0 ]; do
        STEP=60
        [ "$REMAIN" -lt 60 ] && STEP=$REMAIN
        sleep "$STEP"
        REMAIN=$(( REMAIN - STEP ))
    done
    echo "[$(date '+%F %T')] 开始执行定时任务..."
    python main.py && echo "[$(date '+%F %T')] 定时任务完成" || echo "[$(date '+%F %T')] 定时任务失败(退出码 $?)"
done
