#!/bin/bash
# 方案C：per-thread 状态文件
# stdin JSON 包含 session_id，取出来作为文件名前缀
STATE="${1:-idle}"

# 从 stdin 读 JSON，取 session_id（兼容 thread_id / session_id）
JSON=$(cat)
THREAD_ID=$(echo "$JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    # 优先级: session_id > thread_id > turn_id
    tid = d.get('session_id') or d.get('thread_id') or d.get('turn_id') or ''
    print(tid)
except: pass
" 2>/dev/null)

if [ -n "$THREAD_ID" ]; then
    echo "$STATE" > "/tmp/codex_tl_${THREAD_ID}"
else
    # 兜底：写全局状态文件
    echo "$STATE" > /tmp/codex_traffic_light_state
fi
