#!/bin/bash
# One-liner to inject/replace hooks in dev machine Claude Code settings.
# Auto-uses hostname as source-app. Pure replace, never accumulates.
# Usage: just paste and run on any dev machine.

python3 -c "
import json,os,socket
p=os.path.expanduser('~/.claude/settings.json')
c=json.load(open(p)) if os.path.exists(p) else {}
h='python3 ~/rsync_data/hook.py --event-type'
c['hooks']={k:[{'matcher':'','hooks':[{'type':'command','command':f'{h} {k}'+(' --add-chat' if k=='Stop' else '')}]}]
  for k in ['UserPromptSubmit','Stop','SessionStart','SessionEnd','PermissionRequest','PreToolUse','SubagentStop']}
os.makedirs(os.path.dirname(p),exist_ok=True)
json.dump(c,open(p,'w'),indent=2)
print(f'Done: hooks injected (source-app will be: {socket.gethostname()})')
"
