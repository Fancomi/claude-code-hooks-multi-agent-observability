# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A real-time observability dashboard for monitoring multiple Claude Code agent sessions across machines. Python hook scripts intercept Claude Code lifecycle events, POST them to a Bun/SQLite server, which broadcasts via WebSocket to a Vue.js dashboard.

Data flow: `Claude Code -> Hook Scripts (Python/uv) -> HTTP POST -> Bun Server -> SQLite + WebSocket -> Vue Dashboard`

## Commands

Task runner is `just` (justfile at project root). Key commands:

```bash
just install          # Install all deps (server + client)
just start            # Start server + client (foreground)
just stop             # Stop all processes
just server           # Server only (dev/watch mode, port 4000)
just client           # Client only (Vite dev, port 5173)
just server-typecheck # TypeScript type-check server
just client-build     # Production build client
just test-event       # Send test event via curl
just health           # Check if server/client are up
just hook-test <name> # Test a hook script (e.g. just hook-test pre_tool_use)
just db-reset         # Delete SQLite database
```

## Architecture

### Server (`apps/server/`) - Bun + SQLite
- Entry: `src/index.ts` - HTTP API + WebSocket on port 4000
- DB: `src/db.ts` - SQLite via `bun:sqlite` (events, themes tables)
- Auto-cleans stale sessions (closed >5min, empty >1min)
- Uses Bun APIs exclusively (see `apps/server/CLAUDE.md` for Bun conventions)

### Client (`apps/client/`) - Vue 3 + Vite + Tailwind
- Entry: `src/App.vue` with WebSocket connection to server
- Main view: `src/components/EventTimeline.vue` (session cards)
- Composables in `src/composables/` for WebSocket, themes, search, charts
- UI is in Chinese (intentional)

### Hooks (`.claude/hooks/`) - Python scripts via `uv run`
- `send_event.py` - Central event forwarder (all other hooks call this or run alongside it)
- Each hook uses PEP 723 inline metadata for deps (no requirements.txt)
- All hooks MUST exit 0 to avoid blocking Claude Code
- Key flags: `--source-app`, `--add-chat`, `--summarize`, `--notify`
- Utils in `.claude/hooks/utils/` (LLM summarization, TTS, HITL, model extraction)

### Session Status State Machine (in EventTimeline.vue)
- **Running**: Active event within last 30 minutes
- **Waiting**: Last event is Stop/SessionEnd, or idle >30 minutes
- **Review**: Unresponded PermissionRequest or HumanInTheLoop event
- Resume: UserPromptSubmit after Stop transitions back to running

## Key Rules

### REMEMBER: Use source_app + session_id to uniquely identify an agent.

Every hook event includes `source_app` and `session_id`. Display as `"source_app:session_id"` with session_id truncated to first 8 characters.

### Bun-only in server code
Use `bun:sqlite`, `Bun.serve()`, `Bun.file()`. No express, better-sqlite3, ws, or node:fs. See `apps/server/CLAUDE.md`.

### Hook scripts use `uv run --script`
Python hook dependencies are declared inline via PEP 723 script metadata. Run hooks with `uv run <script>.py`.

### Ports are configurable via env vars
`SERVER_PORT` (default 4000), `CLIENT_PORT`/`VITE_PORT` (default 5173), `VITE_API_PORT`. This supports multiple worktrees running in parallel.

### LLM calls use Anthropic Haiku 4.5
Summaries and agent naming use `claude-haiku-4-5-20251001` for speed. Config in `.claude/hooks/utils/llm/anth.py`.
