#!/bin/bash
# Deploy hook script to remote dev machine and generate Claude Code settings.
# Usage: ./deploy.sh [--host 10.52.94.216] [--source-app dev-01]
set -euo pipefail

HOST="${1:-10.52.94.216}"
SOURCE_APP="${2:-dev-01}"
PORT="${RSYNC_PORT:-8022}"
PASSWORD_FILE="${RSYNC_PASSWORD_FILE:-$HOME/rsync_client.passwd}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[deploy] uploading hook.py to $HOST..."
rsync --port="$PORT" --password-file="$PASSWORD_FILE" -az \
  "$SCRIPT_DIR/hook.py" "myuser@${HOST}::data/hook.py"

# Generate settings.json snippet for the dev machine
HOOK_CMD="python3 ~/rsync_data/hook.py --source-app $SOURCE_APP"
cat << EOF

=== Dev machine Claude Code configuration ===
Add to ~/.claude/settings.json on $HOST:

{
  "hooks": {
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "$HOOK_CMD --event-type UserPromptSubmit"}]}],
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "$HOOK_CMD --event-type Stop --add-chat"}]}],
    "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "$HOOK_CMD --event-type SessionStart"}]}],
    "SessionEnd": [{"matcher": "", "hooks": [{"type": "command", "command": "$HOOK_CMD --event-type SessionEnd"}]}],
    "PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "$HOOK_CMD --event-type PermissionRequest"}]}],
    "PreToolUse": [{"matcher": "", "hooks": [{"type": "command", "command": "$HOOK_CMD --event-type PreToolUse"}]}],
    "SubagentStop": [{"matcher": "", "hooks": [{"type": "command", "command": "$HOOK_CMD --event-type SubagentStop"}]}]
  }
}

Then on Mac, start the sync:
  $SCRIPT_DIR/sync.sh --remote myuser@${HOST}::data/events/ --port $PORT

EOF
