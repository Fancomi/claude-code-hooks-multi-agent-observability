#!/usr/bin/env bash
set -euo pipefail

# 一键安装/启动本机 Claude Code 任务看板：
# 1. 安装 Bun/uv（如缺失）
# 2. 安装 server/client 依赖
# 3. 将低噪音 Claude Code hooks 写入 ~/.claude/settings.json
# 4. 启动看板服务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_PORT="${SERVER_PORT:-4000}"
CLIENT_PORT="${CLIENT_PORT:-5173}"
SOURCE_APP="${SOURCE_APP:-mac-local}"
SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
SEND_EVENT="$PROJECT_ROOT/.claude/hooks/send_event.py"
SERVER_URL="http://localhost:${SERVER_PORT}/events"
NO_START=0

export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}==>${NC} $*"; }
ok() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; exit 1; }

usage() {
  cat <<EOF
用法：scripts/install-and-start.sh [选项]

选项：
  --no-start     只安装依赖和写入 hooks，不启动看板
  -h, --help     显示帮助

环境变量：
  SERVER_PORT=4000             服务端端口
  CLIENT_PORT=5173             前端端口
  SOURCE_APP=mac-local         看板中显示的本机名称
  CLAUDE_SETTINGS_FILE=...     Claude Code settings.json 路径
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-start)
        NO_START=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "未知参数：$1"
        ;;
    esac
    shift
  done
}

ensure_bun() {
  if command -v bun >/dev/null 2>&1; then
    ok "Bun 已安装：$(bun --version)"
    return
  fi

  warn "未找到 Bun，开始安装"
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  command -v bun >/dev/null 2>&1 || fail "Bun 安装失败，请手动安装后重试"
  ok "Bun 安装完成：$(bun --version)"
}

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    ok "uv 已安装：$(uv --version)"
    return
  fi

  warn "未找到 uv，开始安装"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1 || fail "uv 安装失败，请手动安装后重试"
  ok "uv 安装完成：$(uv --version)"
}

install_deps() {
  log "安装服务端依赖"
  (cd "$PROJECT_ROOT/apps/server" && bun install)

  log "安装前端依赖"
  (cd "$PROJECT_ROOT/apps/client" && bun install)
}

write_hooks() {
  log "写入 Claude Code hooks：$SETTINGS_FILE"
  mkdir -p "$(dirname "$SETTINGS_FILE")"

  if [ ! -f "$SETTINGS_FILE" ]; then
    printf '{}\n' > "$SETTINGS_FILE"
  fi

  SETTINGS_FILE="$SETTINGS_FILE" \
  SEND_EVENT="$SEND_EVENT" \
  SOURCE_APP="$SOURCE_APP" \
  SERVER_URL="$SERVER_URL" \
  python3 <<'PY'
import json
import os
from pathlib import Path

settings_path = Path(os.environ['SETTINGS_FILE']).expanduser()
send_event = os.environ['SEND_EVENT']
source_app = os.environ['SOURCE_APP']
server_url = os.environ['SERVER_URL']

with settings_path.open() as f:
    data = json.load(f)

hooks = data.setdefault('hooks', {})

# 低噪音：不写入 PreToolUse/PostToolUse，不记录工具细节。
events = {
    'UserPromptSubmit': f'uv run {send_event} --source-app {source_app} --event-type UserPromptSubmit --server-url {server_url}',
    'Stop': f'uv run {send_event} --source-app {source_app} --event-type Stop --add-chat --server-url {server_url}',
    'PermissionRequest': f'uv run {send_event} --source-app {source_app} --event-type PermissionRequest --server-url {server_url}',
    'SessionStart': f'uv run {send_event} --source-app {source_app} --event-type SessionStart --server-url {server_url}',
    'SessionEnd': f'uv run {send_event} --source-app {source_app} --event-type SessionEnd --server-url {server_url}',
}

for event_name, command in events.items():
    # 只替换本项目 send_event.py 相关 hook，保留用户已有的其它 hook。
    existing_entries = hooks.get(event_name, [])
    kept_entries = []
    for entry in existing_entries:
        kept = []
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '')
            if 'claude-code-hooks-multi-agent-observability/.claude/hooks/send_event.py' not in cmd:
                kept.append(hook)
        if kept:
            kept_entries.append({**entry, 'hooks': kept})

    kept_entries.append({
        'matcher': '',
        'hooks': [{
            'type': 'command',
            'command': command,
        }]
    })
    hooks[event_name] = kept_entries

settings_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
PY

  python3 -m json.tool "$SETTINGS_FILE" >/dev/null
  ok "Claude Code hooks 已写入"
}

kill_port() {
  local port="$1"
  local name="$2"
  local pids=""

  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -ti :"$port" 2>/dev/null || true)"
  fi

  if [ -n "$pids" ]; then
    warn "关闭占用 ${name} 端口 ${port} 的进程：$pids"
    for pid in $pids; do
      kill "$pid" 2>/dev/null || true
    done
    sleep 1
  fi
}

start_system() {
  log "启动看板"
  kill_port "$SERVER_PORT" "server"
  kill_port "$CLIENT_PORT" "client"

  "$SCRIPT_DIR/start-system.sh"
}

main() {
  parse_args "$@"

  log "项目目录：$PROJECT_ROOT"
  log "服务端端口：$SERVER_PORT"
  log "前端端口：$CLIENT_PORT"
  log "本机名称：$SOURCE_APP"

  ensure_bun
  ensure_uv
  install_deps
  write_hooks

  ok "安装完成。若当前 Claude Code 会话已经启动，请重启会话或打开 /hooks 让新 hooks 生效。"

  if [ "$NO_START" = "1" ]; then
    ok "已按 --no-start 跳过启动"
    return
  fi

  start_system
}

main "$@"
