# Claude Code 多机任务看板

实时监控多台机器上 Claude Code 会话的任务状态、进展和聊天记录。

## 架构

```
Claude Code (各机器) → Hook 脚本 → HTTP POST → Bun 服务端 → SQLite → WebSocket → Vue 看板
```

## 功能

- **任务总览**：每个会话显示所在机器、任务简述、当前进展、状态（进行中 / 等待 / 待你处理）
- **实时更新**：WebSocket 推送，无需刷新
- **聊天记录**：Stop hook 触发后同步完整对话，可展开查看
- **自动清理**：已关闭会话 5 分钟后自动隐藏；空占位会话 1 分钟后清除
- **Resume 感知**：会话 resume 后正确识别为活跃状态，不显示旧的 Stop 状态
- **中文界面**：隐藏工具调用细节，只展示任务和聊天

## 快速开始

### 本机（Mac 看板）

```bash
# 一键安装依赖、写入 hooks、启动看板
./scripts/install-and-start.sh
```

看板地址：http://localhost:5173

### 远程机器（Linux 开发机）

在每台开发机上，将 hooks 写入 `~/.claude/settings.json`：

```json
{
  "hooks": {
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "uv run /path/to/send_event.py --source-app 机器名 --event-type UserPromptSubmit --server-url http://MAC_IP:4000/events"}]}],
    "Stop":             [{"matcher": "", "hooks": [{"type": "command", "command": "uv run /path/to/send_event.py --source-app 机器名 --event-type Stop --add-chat --server-url http://MAC_IP:4000/events"}]}],
    "PermissionRequest":[{"matcher": "", "hooks": [{"type": "command", "command": "uv run /path/to/send_event.py --source-app 机器名 --event-type PermissionRequest --server-url http://MAC_IP:4000/events"}]}],
    "SessionStart":     [{"matcher": "", "hooks": [{"type": "command", "command": "uv run /path/to/send_event.py --source-app 机器名 --event-type SessionStart --server-url http://MAC_IP:4000/events"}]}],
    "SessionEnd":       [{"matcher": "", "hooks": [{"type": "command", "command": "uv run /path/to/send_event.py --source-app 机器名 --event-type SessionEnd --server-url http://MAC_IP:4000/events"}]}]
  }
}
```

将 `机器名` 替换为可识别的名称（如 `dev-01`），`MAC_IP` 替换为本机 IP。

## 项目结构

```
├── apps/
│   ├── server/src/
│   │   ├── index.ts        # HTTP + WebSocket 服务，自动清理定时器
│   │   ├── db.ts           # SQLite，含 cleanupClosedSessions / cleanupEmptySessions
│   │   └── types.ts
│   └── client/src/
│       ├── App.vue
│       └── components/
│           └── EventTimeline.vue   # 任务看板主组件（会话卡片、状态判断、聊天记录）
├── .claude/hooks/
│   └── send_event.py       # 通用 hook 脚本，支持 --add-chat / --source-app 等参数
└── scripts/
    ├── install-and-start.sh  # 一键安装 + 启动
    └── start-system.sh       # 仅启动
```

## 会话状态逻辑

| 状态 | 触发条件 |
|------|---------|
| 进行中 | 最后事件不是 Stop/SessionEnd，且距今 < 30 分钟 |
| 等待 | 最后事件是 Stop/SessionEnd，或空闲超过 30 分钟 |
| 待你处理 | 最新未响应的 PermissionRequest 或 humanInTheLoop 事件 |

Resume 场景：Stop 之后出现新的 UserPromptSubmit，会话重新标记为进行中。

## 依赖

- [Bun](https://bun.sh/) — 服务端运行时
- [uv](https://docs.astral.sh/uv/) — Python hook 脚本运行器
- Node/Bun — 前端构建（Vite + Vue 3）
