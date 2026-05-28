#!/bin/bash
# Sync hook events from remote dev machines and post to local server.
# Usage: ./sync.sh --remote user@host::module/ [--port 8022] [--interval 3]
set -euo pipefail

INTERVAL="${SYNC_INTERVAL:-3}"
REMOTE="${REMOTE_RSYNC:-myuser@10.52.94.216::data/}"
PORT="${RSYNC_PORT:-8022}"
PASSWORD_FILE="${RSYNC_PASSWORD_FILE:-$HOME/rsync_client.passwd}"
SERVER="${EVENT_SERVER_URL:-http://localhost:4000/events}"
LOCAL="/tmp/remote-agent-events"

while [[ $# -gt 0 ]]; do
  case $1 in
    --interval) INTERVAL="$2"; shift 2;;
    --remote)   REMOTE="$2"; shift 2;;
    --port)     PORT="$2"; shift 2;;
    --server)   SERVER="$2"; shift 2;;
    *) shift;;
  esac
done

mkdir -p "$LOCAL"
echo "[sync] pulling *.event.json from $REMOTE (port $PORT) every ${INTERVAL}s → $SERVER"

while true; do
  # Pull only .event.json files from module root (avoids subdirectory compat issue)
  rsync --port="$PORT" --password-file="$PASSWORD_FILE" \
    -az --include='*.event.json' --exclude='*' --remove-source-files \
    "$REMOTE" "$LOCAL/" 2>/dev/null || true

  for f in "$LOCAL"/*.event.json; do
    [ -f "$f" ] || continue
    if curl -sf -X POST "$SERVER" -H "Content-Type: application/json" -d @"$f" >/dev/null; then
      rm -f "$f"
    fi
  done

  sleep "$INTERVAL"
done
