#!/usr/bin/env python3
"""
Lightweight hook event writer for remote dev machines.
Writes events as .event.json files to rsync-shared directory root.
No external dependencies (stdlib only). Auto-uses hostname as source-app.

Usage: python3 ~/rsync_data/hook.py --event-type Stop --add-chat
"""
import json, sys, os, time, argparse, socket

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-app', default=socket.gethostname())
    parser.add_argument('--event-type', required=True)
    parser.add_argument('--output-dir', default=os.path.expanduser('~/rsync_data'))
    parser.add_argument('--add-chat', action='store_true')
    args = parser.parse_args()

    data = json.loads(sys.stdin.read())
    event = {
        'source_app': args.source_app,
        'session_id': data.get('session_id', ''),
        'hook_event_type': args.event_type,
        'payload': data,
        'timestamp': int(time.time() * 1000)
    }

    if args.add_chat and 'transcript_path' in data:
        try:
            with open(data['transcript_path']) as f:
                event['chat'] = [json.loads(line) for line in f if line.strip()]
        except Exception:
            pass

    os.makedirs(args.output_dir, exist_ok=True)
    sid = event['session_id'][:8]
    filename = f"{event['timestamp']}_{sid}_{args.event_type}.event.json"
    with open(os.path.join(args.output_dir, filename), 'w') as f:
        json.dump(event, f)

if __name__ == '__main__':
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
