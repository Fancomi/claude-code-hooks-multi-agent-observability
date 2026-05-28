<template>
  <div class="cockpit-shell flex-1 overflow-hidden flex flex-col">
    <div class="cockpit-header">
      <div>
        <div class="eyebrow">本机演示看板</div>
        <h2>任务总览</h2>
        <div class="subtitle">只展示任务、状态和聊天记录；隐藏工具调用细节</div>
      </div>
      <div class="header-right">
        <button class="filter-chip" :class="{ active: showHistory }" @click="showHistory = !showHistory">
          {{ showHistory ? '隐藏历史' : '查看历史' }}
        </button>
        <div class="connection-pill" :class="isConnected ? 'online' : 'offline'">
          <span class="connection-dot"></span>
          {{ isConnected ? '实时连接中' : '连接中断' }}
        </div>
        <div class="fleet-stats">
          <div class="stat"><strong>{{ sessionCards.length }}</strong><span>全部会话</span></div>
          <div class="stat running"><strong>{{ runningCount }}</strong><span>进行中</span></div>
          <div class="stat review"><strong>{{ reviewCount }}</strong><span>待你处理</span></div>
        </div>
      </div>
    </div>

    <div class="cockpit-toolbar">
      <input
        type="text"
        v-model="query"
        placeholder="搜索任务、回复、会话号..."
      />
      <div class="app-filter">
        <button
          class="filter-chip"
          :class="{ active: !selectedApp }"
          @click="selectedApp = ''"
        >全部</button>
        <button
          v-for="app in uniqueApps"
          :key="app"
          class="filter-chip"
          :class="{ active: selectedApp === app }"
          @click="selectedApp = app"
        >
          <span class="machine-dot" :style="{ backgroundColor: getHexColorForApp(app) }"></span>
          {{ app }}
        </button>
      </div>
      <div class="toolbar-meta">
        <span>事件 {{ events.length }} 条</span>
        <span v-if="lastEventAt">最近更新 {{ formatRelativeTime(lastEventAt) }}</span>
        <span v-else>等待第一条会话记录</span>
      </div>
    </div>

    <div ref="scrollContainer" class="session-scroll" @scroll="handleScroll">
      <TransitionGroup v-if="visibleSessionCards.length > 0" name="session" tag="div" class="session-list">
        <article
          v-for="card in visibleSessionCards"
          :key="card.key"
          class="session-card"
          :class="`status-${card.status}`"
        >
          <div class="card-topline">
            <div class="machine-block">
              <span class="machine-dot" :style="{ backgroundColor: getHexColorForApp(card.sourceApp) }"></span>
              <span class="machine-name">{{ card.sourceApp }}</span>
              <span class="session-id">会话 {{ card.shortSessionId }}</span>
            </div>
            <div class="status-chip" :class="card.status">{{ card.statusLabel }}</div>
          </div>

          <div class="task-title">{{ card.summary }}</div>

          <div class="progress-block">
            <div class="field-label">当前进展</div>
            <div class="progress-text">{{ card.progress }}</div>
          </div>

          <div v-if="card.status === 'review'" class="reply-box" :class="{ disabled: !card.canReply }">
            <template v-if="card.canReply">
              <div class="reply-title">可在页面回复</div>
              <textarea
                v-model="replyDrafts[card.key]"
                placeholder="输入回复内容..."
                rows="3"
              ></textarea>
              <div class="reply-actions">
                <button @click="submitReply(card)">发送回复</button>
              </div>
            </template>
            <template v-else>
              <div class="reply-title">需要回到终端处理</div>
              <div class="reply-note">当前普通 Claude Code 会话没有可写回通道，页面只能展示状态和聊天记录。</div>
            </template>
          </div>

          <div class="card-meta">
            <span>消息 {{ card.messageCount }} 条</span>
            <span>最近 {{ formatRelativeTime(card.lastTimestamp) }}</span>
            <span>开始 {{ formatClockTime(card.firstTimestamp) }}</span>
            <span v-if="card.modelName">{{ formatModelName(card.modelName) }}</span>
          </div>

          <button class="details-toggle" @click="toggleSession(card.key)">
            {{ expandedSessions.has(card.key) ? '收起聊天记录' : '查看聊天记录' }}
          </button>

          <div v-if="expandedSessions.has(card.key)" class="chat-panel">
            <div v-if="card.messages.length === 0" class="no-chat">
              暂无聊天记录。Stop hook 触发后会同步完整对话。
            </div>
            <div
              v-for="message in card.messages.slice(-16)"
              :key="message.id"
              class="chat-message"
              :class="message.role"
            >
              <div class="role-label">{{ roleLabel(message.role) }}</div>
              <div class="message-text">{{ message.text }}</div>
            </div>
          </div>
        </article>
      </TransitionGroup>

      <div v-else class="empty-state">
        <div class="empty-title">暂无真实会话</div>
        <div class="empty-copy">重启 Claude Code 后，新的任务和聊天记录会实时显示在这里。</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue';
import type { HookEvent } from '../types';
import { useEventColors } from '../composables/useEventColors';
import { API_BASE_URL } from '../config';

const props = defineProps<{
  events: HookEvent[];
  filters: {
    sourceApp: string;
    sessionId: string;
    eventType: string;
  };
  isConnected?: boolean;
  stickToBottom: boolean;
  uniqueAppNames?: string[];
  allAppNames?: string[];
}>();

const emit = defineEmits<{
  'update:stickToBottom': [value: boolean];
  selectAgent: [agentName: string];
}>();

const scrollContainer = ref<HTMLElement>();
const query = ref('');
const selectedApp = ref('');
const showHistory = ref(false);
const expandedSessions = ref(new Set<string>());
const replyDrafts = ref<Record<string, string>>({});
const now = ref(Date.now());
let tick: number | undefined;

const { getHexColorForApp } = useEventColors();

type SessionStatus = 'running' | 'waiting' | 'review';
type ChatRole = 'user' | 'assistant' | 'system';

interface ChatMessage {
  id: string;
  role: ChatRole;
  text: string;
  timestamp?: number;
}

interface SessionCard {
  key: string;
  sourceApp: string;
  sessionId: string;
  shortSessionId: string;
  events: HookEvent[];
  messages: ChatMessage[];
  messageCount: number;
  firstTimestamp: number;
  lastTimestamp: number;
  status: SessionStatus;
  statusLabel: string;
  summary: string;
  progress: string;
  modelName?: string;
  canReply: boolean;
  replyEventId?: number;
}

const uniqueApps = computed(() => {
  return [...new Set(props.events.map(e => e.source_app))].sort();
});

const baseEvents = computed(() => {
  return props.events
    .filter(event => {
      if (props.filters.sourceApp && event.source_app !== props.filters.sourceApp) return false;
      if (props.filters.sessionId && event.session_id !== props.filters.sessionId) return false;
      if (props.filters.eventType && event.hook_event_type !== props.filters.eventType) return false;
      return true;
    })
    .slice()
    .sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));
});

const CLOSED_SESSION_VISIBLE_MS = 30 * 60 * 1000;

const sessionCards = computed<SessionCard[]>(() => {
  // Group by session_id only (same session may report from multiple source_apps)
  const groups = new Map<string, HookEvent[]>();

  for (const event of baseEvents.value) {
    const key = event.session_id;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(event);
  }

  return Array.from(groups.entries())
    .map(([key, events]) => makeSessionCard(key, events))
    .filter(card => !isEmptyPlaceholder(card))
    .filter(card => showHistory.value || !isClosedAndExpired(card))
    .filter(card => card.summary !== '还没有捕获到任务内容')
    .sort((a, b) => {
      const order: Record<SessionStatus, number> = { review: 0, running: 1, waiting: 2 };
      return order[a.status] - order[b.status] || b.lastTimestamp - a.lastTimestamp;
    });
});

const visibleSessionCards = computed(() => {
  let cards = sessionCards.value;

  // Filter by selected source_app
  if (selectedApp.value) {
    cards = cards.filter(card => card.sourceApp === selectedApp.value);
  }

  const q = query.value.trim().toLowerCase();
  if (!q) return cards;

  return cards.filter(card => {
    return [
      card.sourceApp,
      card.sessionId,
      card.summary,
      card.progress,
      card.statusLabel,
      ...card.messages.map(message => message.text)
    ].some(value => value.toLowerCase().includes(q));
  });
});

const runningCount = computed(() => sessionCards.value.filter(card => card.status === 'running').length);
const reviewCount = computed(() => sessionCards.value.filter(card => card.status === 'review').length);
const lastEventAt = computed(() => baseEvents.value[baseEvents.value.length - 1]?.timestamp || 0);

const makeSessionCard = (key: string, events: HookEvent[]): SessionCard => {
  const first = events[0];
  const last = events[events.length - 1];
  const messages = getMessages(events);
  const status = getSessionStatus(events, last);
  const replyEvent = getReplyCapableEvent(events);

  return {
    key,
    sourceApp: first.source_app,
    sessionId: first.session_id,
    shortSessionId: first.session_id.slice(0, 8),
    events,
    messages,
    messageCount: messages.length,
    firstTimestamp: first.timestamp || 0,
    lastTimestamp: last.timestamp || 0,
    status,
    statusLabel: status === 'review' ? '待你处理' : status === 'running' ? '进行中' : '等待',
    summary: getSessionSummary(events, messages),
    progress: getProgressText(events, messages, status),
    modelName: [...events].reverse().find(e => e.model_name)?.model_name,
    canReply: Boolean(replyEvent?.id),
    replyEventId: replyEvent?.id
  };
};

const isEmptyPlaceholder = (card: SessionCard) => {
  return card.events.every(event => event.hook_event_type === 'SessionStart') && card.messages.length === 0;
};

const isClosedAndExpired = (card: SessionCard) => {
  const latestEvent = card.events[card.events.length - 1];
  const isClosed = ['Stop', 'SessionEnd', 'SubagentStop'].includes(latestEvent?.hook_event_type || '');
  if (!isClosed) return false;
  // Don't hide if session was resumed (UserPromptSubmit after Stop)
  const lastStopIdx = card.events.map(e => e.hook_event_type).lastIndexOf('Stop');
  if (lastStopIdx >= 0 && card.events.slice(lastStopIdx + 1).some(e => e.hook_event_type === 'UserPromptSubmit')) return false;
  return now.value - card.lastTimestamp > CLOSED_SESSION_VISIBLE_MS;
};

const getReplyCapableEvent = (events: HookEvent[]) => {
  return [...events].reverse().find(event => {
    return event.id && event.humanInTheLoop?.responseWebSocketUrl && event.humanInTheLoopStatus?.status !== 'responded';
  });
};

const getSessionStatus = (events: HookEvent[], last: HookEvent): SessionStatus => {
  // Find the latest "decision" event after the last Stop/SessionEnd (if any)
  const lastStopIdx = [...events].map(e => e.hook_event_type).lastIndexOf('Stop') !== -1
    ? events.map(e => e.hook_event_type).lastIndexOf('Stop')
    : events.map(e => e.hook_event_type).lastIndexOf('SessionEnd');
  const eventsAfterStop = lastStopIdx >= 0 ? events.slice(lastStopIdx + 1) : events;

  // If there's activity after the last Stop, the session was resumed — treat as active
  const hasActivityAfterStop = eventsAfterStop.some(e =>
    ['UserPromptSubmit', 'PermissionRequest'].includes(e.hook_event_type) || e.humanInTheLoop
  );

  const searchEvents = hasActivityAfterStop ? eventsAfterStop : events;
  const latestDecisionEvent = [...searchEvents].reverse().find(event => {
    return event.hook_event_type === 'PermissionRequest' || event.humanInTheLoop || ['Stop', 'SessionEnd'].includes(event.hook_event_type);
  });

  if (latestDecisionEvent?.hook_event_type === 'PermissionRequest') return 'review';
  if (latestDecisionEvent?.humanInTheLoop && latestDecisionEvent.humanInTheLoopStatus?.status !== 'responded') return 'review';
  if (['Stop', 'SessionEnd', 'SubagentStop'].includes(last.hook_event_type)) return 'waiting';

  // Only mark as waiting after 30 minutes of silence (user may just be thinking)
  const ageMs = now.value - (last.timestamp || 0);
  return ageMs < 30 * 60_000 ? 'running' : 'waiting';
};

const getSessionSummary = (events: HookEvent[], messages: ChatMessage[]) => {
  // Find the latest UserPromptSubmit and the latest Stop with chat
  const lastPromptEvent = [...events].reverse().find(e => e.hook_event_type === 'UserPromptSubmit' && typeof e.payload?.prompt === 'string');
  const lastStopWithChat = [...events].reverse().find(e => Array.isArray(e.chat) && e.chat.length > 0);

  // If there's a prompt AFTER the last chat snapshot, it's the current task
  if (lastPromptEvent && (!lastStopWithChat || (lastPromptEvent.timestamp || 0) > (lastStopWithChat.timestamp || 0))) {
    return `任务：${truncate(lastPromptEvent.payload.prompt, 92)}`;
  }

  const lastUserMessage = [...messages].reverse().find(message => message.role === 'user');
  if (lastUserMessage) return `任务：${truncate(lastUserMessage.text, 92)}`;

  if (lastPromptEvent?.payload?.prompt) return `任务：${truncate(lastPromptEvent.payload.prompt, 92)}`;

  return '还没有捕获到任务内容';
};

const getProgressText = (events: HookEvent[], messages: ChatMessage[], status: SessionStatus) => {
  if (status === 'review') return '需要你确认、授权或回复';

  const lastAssistantMessage = [...messages].reverse().find(message => message.role === 'assistant');
  if (lastAssistantMessage) return `最新回复：${truncate(lastAssistantMessage.text, 118)}`;

  const last = events[events.length - 1];
  if (last.hook_event_type === 'Stop' || last.hook_event_type === 'SessionEnd') {
    return '本轮已结束，等待下一条指令';
  }
  if (status === 'running') return 'Claude 已收到任务，正在处理';
  return '等待下一条指令';
};

const getMessages = (events: HookEvent[]): ChatMessage[] => {
  const stopWithChat = [...events].reverse().find(event => Array.isArray(event.chat) && event.chat.length > 0);
  const transcriptMessages = stopWithChat?.chat ? extractTranscriptMessages(stopWithChat.chat) : [];
  if (transcriptMessages.length > 0) return transcriptMessages;

  return events
    .filter(event => event.hook_event_type === 'UserPromptSubmit' && typeof event.payload?.prompt === 'string')
    .map((event, index) => ({
      id: `${event.id || event.timestamp || index}-prompt`,
      role: 'user' as ChatRole,
      text: event.payload.prompt,
      timestamp: event.timestamp
    }));
};

const extractTranscriptMessages = (chat: any[]): ChatMessage[] => {
  return chat.flatMap((entry, index) => {
    const role = normalizeRole(entry?.message?.role || entry?.role || entry?.type);
    const content = entry?.message?.content ?? entry?.content;
    const text = extractText(content);

    if (!role || !text) return [];

    return [{
      id: `${entry?.uuid || entry?.id || index}`,
      role,
      text: truncate(text, 1200),
      timestamp: entry?.timestamp ? Date.parse(entry.timestamp) : undefined
    }];
  });
};

const normalizeRole = (role: string | undefined): ChatRole | '' => {
  if (role === 'user') return 'user';
  if (role === 'assistant') return 'assistant';
  if (role === 'system') return 'system';
  return '';
};

const extractText = (content: any): string => {
  if (typeof content === 'string') return content.trim();
  if (!Array.isArray(content)) return '';

  return content
    .flatMap(part => {
      if (typeof part === 'string') return [part];
      if (part?.type === 'text' && typeof part.text === 'string') return [part.text];
      return [];
    })
    .join('\n')
    .trim();
};

const truncate = (value: string, max: number) => {
  const compact = value.replace(/\s+/g, ' ').trim();
  return compact.length > max ? `${compact.slice(0, max - 1)}…` : compact;
};

const roleLabel = (role: ChatRole) => {
  if (role === 'user') return '你';
  if (role === 'assistant') return 'Claude';
  return '系统';
};

const formatRelativeTime = (timestamp?: number) => {
  if (!timestamp) return '-';
  const diff = Math.max(0, now.value - timestamp);
  if (diff < 5_000) return '刚刚';
  if (diff < 60_000) return `${Math.floor(diff / 1000)} 秒前`;
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)} 分钟前`;
  return `${Math.floor(diff / 3_600_000)} 小时前`;
};

const formatClockTime = (timestamp?: number) => {
  if (!timestamp) return '-';
  return new Date(timestamp).toLocaleTimeString('zh-CN', {
    hour: '2-digit',
    minute: '2-digit'
  });
};

const formatModelName = (name: string) => {
  const parts = name.split('-');
  if (parts.length >= 4) return `${parts[1]}-${parts[2]}-${parts[3]}`;
  return name;
};

const toggleSession = (key: string) => {
  const next = new Set(expandedSessions.value);
  next.has(key) ? next.delete(key) : next.add(key);
  expandedSessions.value = next;
};

const submitReply = async (card: SessionCard) => {
  const response = replyDrafts.value[card.key]?.trim();
  if (!response || !card.replyEventId) return;

  await fetch(`${API_BASE_URL}/events/${card.replyEventId}/respond`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ response })
  });

  replyDrafts.value[card.key] = '';
};

const scrollToBottom = () => {
  if (scrollContainer.value) {
    scrollContainer.value.scrollTop = scrollContainer.value.scrollHeight;
  }
};

const handleScroll = () => {
  if (!scrollContainer.value) return;
  const { scrollTop, scrollHeight, clientHeight } = scrollContainer.value;
  const isAtBottom = scrollHeight - scrollTop - clientHeight < 50;
  if (isAtBottom !== props.stickToBottom) emit('update:stickToBottom', isAtBottom);
};

watch(() => props.events.length, async () => {
  if (props.stickToBottom) {
    await nextTick();
    scrollToBottom();
  }
});

watch(() => props.stickToBottom, (shouldStick) => {
  if (shouldStick) scrollToBottom();
});

onMounted(() => {
  tick = window.setInterval(() => {
    now.value = Date.now();
  }, 5_000);
});

onUnmounted(() => {
  if (tick) window.clearInterval(tick);
});
</script>

<style scoped>
.cockpit-shell {
  background:
    radial-gradient(circle at top left, rgba(56, 189, 248, 0.10), transparent 34rem),
    linear-gradient(180deg, #070a0f 0%, #0b1118 100%);
  color: #d8dee9;
  border-top: 1px solid rgba(148, 163, 184, 0.16);
}

.cockpit-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: 24px;
  padding: 22px 28px 16px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.12);
}

.header-right {
  display: flex;
  align-items: flex-end;
  gap: 14px;
}

.eyebrow {
  color: #64748b;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  letter-spacing: 0.18em;
  font-weight: 700;
}

h2 {
  margin: 4px 0 0;
  font-size: 28px;
  line-height: 1;
  color: #f8fafc;
  letter-spacing: -0.04em;
}

.subtitle {
  margin-top: 8px;
  color: #64748b;
  font-size: 13px;
}

.connection-pill {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 999px;
  padding: 7px 10px;
  color: #94a3b8;
  background: rgba(15, 23, 42, 0.72);
  font-size: 12px;
  font-weight: 800;
  white-space: nowrap;
}

.connection-dot {
  width: 8px;
  height: 8px;
  border-radius: 999px;
  background: currentColor;
}

.connection-pill.online { color: #22c55e; }
.connection-pill.offline { color: #ef4444; }

.fleet-stats {
  display: flex;
  gap: 10px;
}

.stat {
  min-width: 86px;
  padding: 8px 10px;
  border: 1px solid rgba(148, 163, 184, 0.14);
  background: rgba(15, 23, 42, 0.72);
  border-radius: 10px;
  text-align: right;
}

.stat strong {
  display: block;
  color: #f8fafc;
  font-size: 20px;
  line-height: 1;
}

.stat span {
  color: #64748b;
  font-size: 11px;
}

.stat.running strong { color: #22c55e; }
.stat.review strong { color: #f59e0b; }

.cockpit-toolbar {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 12px 28px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.10);
  background: rgba(2, 6, 23, 0.42);
}

.cockpit-toolbar input {
  width: min(520px, 55vw);
  background: rgba(15, 23, 42, 0.82);
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 9px;
  color: #e2e8f0;
  font-size: 13px;
  outline: none;
  padding: 9px 11px;
}

.cockpit-toolbar input:focus { border-color: rgba(56, 189, 248, 0.58); }

.app-filter {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}
.filter-chip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 10px;
  border-radius: 6px;
  font-size: 12px;
  border: 1px solid rgba(148, 163, 184, 0.18);
  background: rgba(15, 23, 42, 0.6);
  color: #94a3b8;
  cursor: pointer;
  transition: all 0.15s;
}
.filter-chip:hover { border-color: rgba(56, 189, 248, 0.4); color: #e2e8f0; }
.filter-chip.active { border-color: rgba(56, 189, 248, 0.6); background: rgba(56, 189, 248, 0.1); color: #38bdf8; }
.filter-chip .machine-dot { width: 7px; height: 7px; border-radius: 50%; }

.toolbar-meta {
  display: flex;
  gap: 14px;
  color: #64748b;
  font-size: 13px;
}

.session-scroll {
  flex: 1;
  overflow-y: auto;
  padding: 20px 28px 28px;
}

.session-list {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
  gap: 14px;
}

.session-card {
  position: relative;
  overflow: hidden;
  border: 1px solid rgba(148, 163, 184, 0.14);
  border-radius: 16px;
  background:
    linear-gradient(180deg, rgba(15, 23, 42, 0.92), rgba(2, 6, 23, 0.94));
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.26);
  padding: 16px;
}

.session-card::before {
  content: '';
  position: absolute;
  inset: 0 auto 0 0;
  width: 4px;
  opacity: 0.95;
}

.session-card.status-running::before { background: #22c55e; }
.session-card.status-review::before { background: #f59e0b; }
.session-card.status-waiting::before { background: #64748b; }

.card-topline {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.machine-block {
  display: flex;
  align-items: center;
  gap: 9px;
  min-width: 0;
}

.machine-dot {
  width: 9px;
  height: 9px;
  border-radius: 999px;
  box-shadow: 0 0 18px currentColor;
  flex: 0 0 auto;
}

.machine-name {
  color: #f8fafc;
  font-weight: 800;
  letter-spacing: -0.02em;
}

.session-id {
  color: #64748b;
  font-size: 12px;
  border-left: 1px solid rgba(148, 163, 184, 0.18);
  padding-left: 9px;
}

.status-chip {
  flex: 0 0 auto;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 800;
  padding: 4px 10px;
}

.status-chip.running { color: #052e16; background: #22c55e; }
.status-chip.review { color: #451a03; background: #f59e0b; }
.status-chip.waiting { color: #cbd5e1; background: #334155; }

.task-title {
  margin-top: 14px;
  color: #e2e8f0;
  font-size: 16px;
  line-height: 1.45;
  font-weight: 700;
}

.progress-block {
  margin-top: 14px;
  padding: 11px 12px;
  background: rgba(15, 23, 42, 0.72);
  border: 1px solid rgba(148, 163, 184, 0.10);
  border-radius: 12px;
}

.field-label {
  color: #64748b;
  font-size: 12px;
  font-weight: 800;
  margin-bottom: 5px;
}

.progress-text {
  color: #94a3b8;
  font-size: 13px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.reply-box {
  margin-top: 12px;
  padding: 12px;
  border-radius: 12px;
  border: 1px solid rgba(245, 158, 11, 0.36);
  background: rgba(245, 158, 11, 0.08);
}

.reply-box.disabled {
  border-color: rgba(148, 163, 184, 0.14);
  background: rgba(15, 23, 42, 0.55);
}

.reply-title {
  color: #f8fafc;
  font-size: 13px;
  font-weight: 900;
  margin-bottom: 8px;
}

.reply-note {
  color: #94a3b8;
  font-size: 13px;
  line-height: 1.5;
}

.reply-box textarea {
  width: 100%;
  resize: vertical;
  min-height: 78px;
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 10px;
  background: rgba(2, 6, 23, 0.72);
  color: #e2e8f0;
  padding: 10px;
  outline: none;
  font-size: 13px;
}

.reply-box textarea:focus {
  border-color: rgba(56, 189, 248, 0.58);
}

.reply-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 8px;
}

.reply-actions button {
  border: 0;
  border-radius: 999px;
  background: #38bdf8;
  color: #082f49;
  font-size: 13px;
  font-weight: 900;
  padding: 7px 13px;
  cursor: pointer;
}

.card-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 14px;
  margin-top: 12px;
  color: #64748b;
  font-size: 12px;
}

.details-toggle {
  margin-top: 14px;
  color: #38bdf8;
  background: transparent;
  border: 0;
  padding: 0;
  font-size: 13px;
  font-weight: 800;
  cursor: pointer;
}

.chat-panel {
  margin-top: 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  max-height: 420px;
  overflow-y: auto;
  border: 1px solid rgba(148, 163, 184, 0.12);
  border-radius: 12px;
  padding: 12px;
  background: #05070b;
}

.no-chat {
  color: #64748b;
  font-size: 13px;
  text-align: center;
  padding: 18px 8px;
}

.chat-message {
  display: grid;
  grid-template-columns: 56px 1fr;
  gap: 10px;
  align-items: start;
}

.role-label {
  font-size: 12px;
  font-weight: 900;
  text-align: right;
  padding-top: 2px;
}

.chat-message.user .role-label { color: #38bdf8; }
.chat-message.assistant .role-label { color: #22c55e; }
.chat-message.system .role-label { color: #a78bfa; }

.message-text {
  color: #cbd5e1;
  font-size: 13px;
  line-height: 1.55;
  white-space: pre-wrap;
  word-break: break-word;
}

.empty-state {
  border: 1px dashed rgba(148, 163, 184, 0.18);
  border-radius: 18px;
  padding: 54px 20px;
  text-align: center;
  background: rgba(15, 23, 42, 0.42);
}

.empty-title {
  color: #e2e8f0;
  font-size: 18px;
  font-weight: 800;
}

.empty-copy {
  margin-top: 6px;
  color: #64748b;
  font-size: 13px;
}

.session-enter-active { transition: all 0.22s ease; }
.session-enter-from { opacity: 0; transform: translateY(-8px); }
.session-leave-active { transition: all 0.18s ease; }
.session-leave-to { opacity: 0; transform: translateY(8px); }

@media (max-width: 720px) {
  .cockpit-header { align-items: flex-start; flex-direction: column; padding: 16px; }
  .header-right { width: 100%; align-items: stretch; flex-direction: column; }
  .fleet-stats { width: 100%; }
  .stat { flex: 1; }
  .cockpit-toolbar { padding: 10px 16px; flex-direction: column; align-items: stretch; }
  .cockpit-toolbar input { width: 100%; }
  .toolbar-meta { flex-direction: column; gap: 4px; }
  .session-scroll { padding: 14px 16px; }
}
</style>
