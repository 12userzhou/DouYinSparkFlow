#!/bin/bash
# 更新 .env 中的 Cookie
# 用法：
#   1) 交互式：bash update_cookie.sh
#   2) 从文件读：bash update_cookie.sh cookies.txt
#   3) 多账号：bash update_cookie.sh U1 cookies.txt   (第一个参数为 unique_id 大写)
set -e

cd "$(dirname "$0")"

ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    echo "[错误] 未找到 .env 文件，请先在项目根目录创建。"
    exit 1
fi

# 解析参数
UNIQUE_ID="U1"
COOKIE_SOURCE=""
if [ "$#" -ge 2 ]; then
    UNIQUE_ID="$1"
    COOKIE_SOURCE="$2"
elif [ "$#" -eq 1 ]; then
    COOKIE_SOURCE="$1"
fi

COOKIE_KEY="COOKIES_${UNIQUE_ID}"

echo "=========================================="
echo "  更新 Cookie: $COOKIE_KEY"
echo "=========================================="

# 读取 cookie JSON
if [ -n "$COOKIE_SOURCE" ] && [ -f "$COOKIE_SOURCE" ]; then
    COOKIE_JSON=$(cat "$COOKIE_SOURCE")
    echo "[信息] 从文件 $COOKIE_SOURCE 读取到 cookie"
else
    echo ""
    echo "请把从浏览器导出的 Cookie JSON 数组（单行或多行均可）粘贴在下面，"
    echo "输入完成后按 Ctrl+D 结束："
    echo ""
    COOKIE_JSON=""
    while IFS= read -r line; do
        COOKIE_JSON="${COOKIE_JSON}${line}"
    done
fi

# 去除首尾空白
COOKIE_JSON="$(echo "$COOKIE_JSON" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [ -z "$COOKIE_JSON" ]; then
    echo "[错误] 未读取到 cookie 内容，已退出。"
    exit 1
fi

# 简单校验：必须是 JSON 数组
case "$COOKIE_JSON" in
    \[*\]) ;;
    *)
        echo "[错误] Cookie 不是 JSON 数组格式（应以 [ 开头、] 结尾），请检查后重试。"
        echo "       前 80 字符: ${COOKIE_JSON:0:80}"
        exit 1
        ;;
esac

# 备份原 .env
cp "$ENV_FILE" "${ENV_FILE}.bak"
echo "[信息] 已备份原配置为 ${ENV_FILE}.bak"

# 用 python 安全替换（避免特殊字符坑坏 sed）
NEW_ENV=$(python3 - "$ENV_FILE" "$COOKIE_KEY" "$COOKIE_JSON" <<'PY'
import sys
env_file, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(env_file, "r", encoding="utf-8") as f:
    lines = f.readlines()
found = False
out = []
for line in lines:
    if line.startswith(f"{key}=") or line.startswith(f"{key} ="):
        out.append(f"{key}={value}\n")
        found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}={value}\n")
with open(env_file, "w", encoding="utf-8") as f:
    f.writelines(out)
print("[信息] 已写入 .env")
PY
)
echo "$NEW_ENV"

echo ""
echo "=========================================="
echo "  Cookie 更新完成！"
echo "=========================================="
echo ""
echo "建议立即跑一次验证："
echo "  source venv/bin/activate && python -u main.py 2>&1 | tee /tmp/run.log"
echo ""
echo "如果运行后出现『检测到登录/扫码页面，cookie 可能已失效』，"
echo "说明新 cookie 仍然无效，请重新从浏览器导出。"
