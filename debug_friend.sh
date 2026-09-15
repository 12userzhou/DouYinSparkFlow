#!/bin/bash
# 排查好友匹配问题：从日志中找出接口返回的所有好友标识
# 用法: bash debug_friend.sh
cd "$(dirname "$0")"

echo "===== 1. 接口返回的所有好友（去重，按昵称排序）====="
grep "接口返回好友" logs/app.log | sort -u

echo ""
echo "===== 2. 昵称里含空白/不可见字符的好友 ====="
grep "接口返回好友" logs/app.log | sort -u | grep -E "nickname=\s+|nickname=$|nickname=[^,]*[[:space:]][^,]*unique_id=" || echo "(无)"

echo ""
echo "===== 3. 用 python 精确找零宽字符昵称的好友 ====="
python3 - <<'PY'
import re

seen = set()
with open("logs/app.log", "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        m = re.search(r"接口返回好友: nickname=(.*), unique_id=(\S*), short_id=(\S*)", line)
        if not m:
            continue
        nick, uid, sid = m.groups()
        if nick in seen:
            continue
        seen.add(nick)
        # 零宽字符 / 纯空白昵称检测
        stripped = nick.replace("\u200b", "").replace("\u200c", "").replace("\u200d", "").replace("\ufeff", "").strip()
        if not stripped:
            print(f"[空白/零宽昵称] 昵称字节={nick.encode('unicode_escape')} unique_id={uid!r} short_id={sid!r}")

if not seen:
    print("(日志里没有任何接口返回好友记录)")
print(f"\n共解析到 {len(seen)} 个不同昵称的好友")
PY
