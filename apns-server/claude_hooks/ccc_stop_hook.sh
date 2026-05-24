#!/bin/bash
# CcCompanion Claude Code Stop hook
#
# Trigger: Claude Code 自动在每个 chain turn 结束时调一次. 这里读 transcript
# 抓最近这一 turn 的 assistant 文本, POST 给本地 apns-server /chat/append,
# server 再 push 到 iPhone.
#
# 配置方式 (一次性):
#   1. cp 这一份到 ~/.claude/hooks/ccc_stop_hook.sh
#   2. chmod +x ~/.claude/hooks/ccc_stop_hook.sh
#   3. 编辑 ~/.claude/settings.json 加 hook 引用 (注意 nested hooks array):
#      {
#        "hooks": {
#          "Stop": [
#            {
#              "matcher": "",
#              "hooks": [
#                {
#                  "type": "command",
#                  "command": "$HOME/.claude/hooks/ccc_stop_hook.sh"
#                }
#              ]
#            }
#          ]
#        }
#      }
#   4. 重启 Claude Code (退出 tmux session 重进, 让 hook config 生效)
#
# 验证 hook 跑通:
#   iPhone 端 ccc 发一条 "hi"; Mac 上 cc 回复后, 看
#   tail -f /tmp/ccc_stop_hook.log
#   应该看到 "posted to /chat/append ok"
#
# Env:
#   CCC_SERVER_URL  default http://127.0.0.1:8795
#   CCC_AUTH_TOKEN  shared_secret 跟 server config.toml 对齐 (写接口必须)

set -uo pipefail

echo "[$(date +%Y-%m-%d\ %H:%M:%S)] hook invoked pid=$$ TMUX_PANE=${TMUX_PANE:-unset}" >> /tmp/ccc_stop_hook.log

# Only run inside ccc-chat tmux pane — skip for tg-ember and other sessions.
# Try TMUX_PANE first; if unset (Claude Code >=2.1.146 stopped propagating it),
# match our ancestor PID against the ccc-chat pane PID.
CURRENT_SESSION=""
if [ -n "${TMUX_PANE:-}" ]; then
    CURRENT_SESSION=$(tmux display-message -t "$TMUX_PANE" -p '#{session_name}' 2>/dev/null || echo "")
else
    CCC_PANE_PID=$(tmux list-panes -t ccc-chat -F '#{pane_pid}' 2>/dev/null | head -1)
    if [ -n "$CCC_PANE_PID" ]; then
        _pid=$$
        while [ "$_pid" -gt 1 ] 2>/dev/null; do
            if [ "$_pid" = "$CCC_PANE_PID" ]; then
                CURRENT_SESSION="ccc-chat"
                break
            fi
            _pid=$(awk '{print $4}' /proc/$_pid/stat 2>/dev/null || echo 0)
        done
    fi
fi
if [ "$CURRENT_SESSION" != "ccc-chat" ]; then
    exit 0
fi

SERVER_URL="${CCC_SERVER_URL:-http://127.0.0.1:8795}"
AUTH_TOKEN="${CCC_AUTH_TOKEN:-}"
# 兜底从 server 自动生成的 secret 文件读
if [ -z "$AUTH_TOKEN" ] && [ -f "$HOME/.ots/secret" ]; then
    AUTH_TOKEN=$(cat "$HOME/.ots/secret" 2>/dev/null)
fi

LOG_PATH="/tmp/ccc_stop_hook.log"
log() { echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $*" >> "$LOG_PATH"; }

# Claude Code 通过 stdin 传 {session_id, transcript_path, cwd, hook_event_name,
# stop_hook_active, last_assistant_message?}.
# 新版 Claude Code 直接传 last_assistant_message; 没有时 fallback 反扫 transcript.
INPUT=$(cat 2>/dev/null || echo "{}")

# 一次性 parse 出 transcript_path 加 last_assistant_message
PARSED=$(echo "$INPUT" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "{}")
    print(d.get("transcript_path") or "")
    print(d.get("last_assistant_message") or "")
except Exception:
    print("")
    print("")
' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$PARSED" | sed -n '1p')
DIRECT_LAST=$(echo "$PARSED" | sed -n '2,$p')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    log "no transcript path (stdin=$INPUT)"
    exit 0
fi

# Always extract thinking blocks from transcript (stdin last_assistant_message never includes them)
# Wait for transcript to flush — hook may fire before the final write
sleep 1
THINKING_TEXT=""
if [ -f "$TRANSCRIPT_PATH" ]; then
    REVERSE_CAT_T="tail -r"
    if ! tail -r /dev/null 2>/dev/null; then REVERSE_CAT_T="tac"; fi
    THINKING_TEXT=$($REVERSE_CAT_T "$TRANSCRIPT_PATH" | python3 -c '
import json, sys
parts = []
def is_real_user(obj):
    """Distinguish a typed user message from a tool_result wrapped as user."""
    if obj.get("type") != "user": return False
    content = obj.get("message", {}).get("content")
    if isinstance(content, str): return True  # plain text user
    if isinstance(content, list):
        # tool_result entries are NOT real user input
        return not any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content)
    return False
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if is_real_user(obj): break
    if obj.get("type") == "assistant":
        for c in obj.get("message", {}).get("content", []):
            if isinstance(c, dict) and c.get("type") == "thinking" and c.get("thinking"):
                parts.append(c["thinking"])
parts.reverse()
if parts: print("💭" + "\n".join(parts))
' 2>/dev/null)
fi

# Prefer stdin last_assistant_message (新版 Claude Code 直接给), fallback transcript
if [ -n "$DIRECT_LAST" ]; then
    LAST_ASSISTANT="$DIRECT_LAST"
    log "using stdin last_assistant_message (chars=${#LAST_ASSISTANT}) thinking=${#THINKING_TEXT}"
else
    # Claude Code transcript flush 慢 — 等 file size 稳定 (连续两次相等 或最长 ~3 秒)
    LAST_SIZE=-1
    STABLE_COUNT=0
    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 0.3
        CUR_SIZE=$(stat -f '%z' "$TRANSCRIPT_PATH" 2>/dev/null \
                || stat -c '%s' "$TRANSCRIPT_PATH" 2>/dev/null \
                || echo "0")
        if [ "$CUR_SIZE" = "$LAST_SIZE" ]; then
            STABLE_COUNT=$((STABLE_COUNT + 1))
            [ "$STABLE_COUNT" -ge 2 ] && break
        else
            STABLE_COUNT=0
        fi
        LAST_SIZE=$CUR_SIZE
    done

    # transcript 是 JSONL 一行一条 message
    # 倒着读 抓自上次 user 以来的所有 assistant text part 然后 join
    # Linux 没 tail -r 用 tac
    REVERSE_CAT="tail -r"
    if ! command -v tail >/dev/null 2>&1 || ! tail -r /dev/null 2>/dev/null; then
        REVERSE_CAT="tac"
    fi
    LAST_ASSISTANT=$($REVERSE_CAT "$TRANSCRIPT_PATH" | python3 -c '
import json, sys
text_parts = []
think_parts = []
def is_real_user(obj):
    if obj.get("type") != "user": return False
    content = obj.get("message", {}).get("content")
    if isinstance(content, str): return True
    if isinstance(content, list):
        return not any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content)
    return False
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if is_real_user(obj): break
    if obj.get("type") == "assistant":
        for c in obj.get("message", {}).get("content", []):
            if not isinstance(c, dict): continue
            if c.get("type") == "text" and c.get("text"):
                text_parts.append(c["text"])
            elif c.get("type") == "thinking" and c.get("thinking"):
                think_parts.append(c["thinking"])
text_parts.reverse()
think_parts.reverse()
if text_parts:
    print("\n".join(text_parts))
elif think_parts:
    print("\n".join(think_parts))
' 2>/dev/null)
fi

if [ -z "$LAST_ASSISTANT" ]; then
    log "empty assistant text — skip"
    exit 0
fi

# POST thinking 单独一条 (如果有)
if [ -n "$THINKING_TEXT" ]; then
    THINK_PAYLOAD=$(THINK_TEXT="$THINKING_TEXT" python3 -c '
import json, os, datetime
ts = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
print(json.dumps({
    "role": "assistant",
    "text": os.environ["THINK_TEXT"],
    "source": "ccc-stop-hook",
    "ts": ts,
}))
')
    curl -s -o /dev/null \
        -X POST "$SERVER_URL/chat/append" \
        -H "Content-Type: application/json" \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        --data "$THINK_PAYLOAD" \
        --max-time 8 2>>"$LOG_PATH"
    log "posted thinking (chars=${#THINKING_TEXT})"
fi

# POST 到 /chat/append
PAYLOAD=$(ASSISTANT_TEXT="$LAST_ASSISTANT" python3 -c '
import json, os, datetime
ts = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
print(json.dumps({
    "role": "assistant",
    "text": os.environ["ASSISTANT_TEXT"],
    "source": "ccc-stop-hook",
    "ts": ts,
}))
')

# retry transient network errors (000/502/503/504), don't retry 401 (auth)
attempt=0
while [ $attempt -lt 3 ]; do
    HTTP_CODE=$(curl -s -o /tmp/ccc_stop_hook.curlout -w "%{http_code}" \
        -X POST "$SERVER_URL/chat/append" \
        -H "Content-Type: application/json" \
        -H "X-Auth-Token: $AUTH_TOKEN" \
        --data "$PAYLOAD" \
        --max-time 8 2>>"$LOG_PATH")
    case "$HTTP_CODE" in
        200) break ;;
        000|502|503|504)
            attempt=$((attempt + 1))
            log "POST retry $attempt http=$HTTP_CODE"
            sleep 1
            ;;
        401)
            log "POST 401 unauthorized — check CCC_AUTH_TOKEN or ~/.ots/secret matches server config.toml shared_secret"
            break
            ;;
        *)
            break
            ;;
    esac
done

if [ "$HTTP_CODE" = "200" ]; then
    log "posted to /chat/append ok (chars=${#LAST_ASSISTANT})"
else
    log "POST /chat/append failed http=$HTTP_CODE body=$(cat /tmp/ccc_stop_hook.curlout 2>/dev/null | head -c 200)"
fi

exit 0
