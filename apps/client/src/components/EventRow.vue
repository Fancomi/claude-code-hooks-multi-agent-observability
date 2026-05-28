<template>
  <div>
    <!-- HITL Question Section (NEW) -->
    <div
      v-if="event.humanInTheLoop && (event.humanInTheLoopStatus?.status === 'pending' || hasSubmittedResponse)"
      class="mb-4 p-4 rounded-lg border-2 shadow-lg"
      :class="hasSubmittedResponse || event.humanInTheLoopStatus?.status === 'responded' ? 'border-green-500 bg-gradient-to-r from-green-50 to-green-100 dark:from-green-900/20 dark:to-green-800/20' : 'border-yellow-500 bg-gradient-to-r from-yellow-50 to-yellow-100 dark:from-yellow-900/20 dark:to-yellow-800/20 animate-pulse-slow'"
      @click.stop
    >
      <!-- Question Header -->
      <div class="mb-3">
        <div class="flex items-center justify-between mb-2">
          <div class="flex items-center space-x-2">
            <span class="text-2xl">{{ hitlTypeEmoji }}</span>
            <h3 class="text-lg font-bold" :class="hasSubmittedResponse || event.humanInTheLoopStatus?.status === 'responded' ? 'text-green-900 dark:text-green-100' : 'text-yellow-900 dark:text-yellow-100'">
              {{ hitlTypeLabel }}
            </h3>
            <span v-if="permissionType" class="text-xs font-mono font-semibold px-2 py-1 rounded border-2 bg-blue-50 dark:bg-blue-900/20 border-blue-500 text-blue-900 dark:text-blue-100">
              {{ permissionType }}
            </span>
          </div>
          <span v-if="!hasSubmittedResponse && event.humanInTheLoopStatus?.status !== 'responded'" class="text-xs font-semibold text-yellow-700 dark:text-yellow-300">
            ⏱️ Waiting for response...
          </span>
        </div>
        <div class="flex items-center space-x-2 ml-9">
          <span
            class="text-xs font-semibold text-[var(--theme-text-primary)] px-1.5 py-0.5 rounded-full border-2 bg-[var(--theme-bg-tertiary)] shadow-sm"
            :style="{ ...appBgStyle, ...appBorderStyle }"
          >
            {{ event.source_app }}
          </span>
          <span class="text-xs text-[var(--theme-text-secondary)] px-1.5 py-0.5 rounded-full border bg-[var(--theme-bg-tertiary)]/50 shadow-sm" :class="borderColorClass">
            {{ sessionIdShort }}
          </span>
          <span class="text-xs text-[var(--theme-text-tertiary)] font-medium">
            {{ formatTime(event.timestamp) }}
          </span>
        </div>
      </div>

      <!-- Question Text -->
      <div class="mb-4 p-3 bg-white dark:bg-gray-800 rounded-lg border" :class="hasSubmittedResponse || event.humanInTheLoopStatus?.status === 'responded' ? 'border-green-300' : 'border-yellow-300'">
        <p class="text-base font-medium text-gray-900 dark:text-gray-100">
          {{ event.humanInTheLoop.question }}
        </p>
      </div>

      <!-- Inline Response Display (Optimistic UI) -->
      <div v-if="localResponse || (event.humanInTheLoopStatus?.status === 'responded' && event.humanInTheLoopStatus.response)" class="mb-4 p-3 bg-white dark:bg-gray-800 rounded-lg border border-green-400">
        <div class="flex items-center mb-2">
          <span class="text-xl mr-2">✅</span>
          <strong class="text-green-900 dark:text-green-100">Your Response:</strong>
        </div>
        <div v-if="(localResponse?.response || event.humanInTheLoopStatus?.response?.response)" class="text-gray-900 dark:text-gray-100 ml-7">
          {{ localResponse?.response || event.humanInTheLoopStatus?.response?.response }}
        </div>
        <div v-if="(localResponse?.permission !== undefined || event.humanInTheLoopStatus?.response?.permission !== undefined)" class="text-gray-900 dark:text-gray-100 ml-7">
          {{ (localResponse?.permission ?? event.humanInTheLoopStatus?.response?.permission) ? 'Approved ✅' : 'Denied ❌' }}
        </div>
        <div v-if="(localResponse?.choice || event.humanInTheLoopStatus?.response?.choice)" class="text-gray-900 dark:text-gray-100 ml-7">
          {{ localResponse?.choice || event.humanInTheLoopStatus?.response?.choice }}
        </div>
      </div>

      <!-- Response UI -->
      <div v-if="event.humanInTheLoop.type === 'question'">
        <!-- Text Input for Questions -->
        <textarea
          v-model="responseText"
          class="w-full p-3 border-2 border-yellow-500 rounded-lg focus:ring-2 focus:ring-yellow-500 focus:border-transparent resize-none"
          rows="3"
          placeholder="Type your response here..."
          @click.stop
        ></textarea>
        <div class="flex justify-end space-x-2 mt-2">
          <button
            @click.stop="submitResponse"
            :disabled="!responseText.trim() || isSubmitting || hasSubmittedResponse"
            class="px-4 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white font-bold rounded-lg transition-all duration-200 shadow-md hover:shadow-lg transform hover:scale-105 disabled:transform-none disabled:cursor-not-allowed"
          >
            {{ isSubmitting ? '⏳ Sending...' : '✅ Submit Response' }}
          </button>
        </div>
      </div>

      <div v-else-if="event.humanInTheLoop.type === 'permission'">
        <!-- Yes/No Buttons for Permissions -->
        <div class="flex justify-end items-center space-x-3">
          <div v-if="hasSubmittedResponse || event.humanInTheLoopStatus?.status === 'responded'" class="flex items-center px-3 py-2 bg-green-100 dark:bg-green-900/30 rounded-lg border border-green-500">
            <span class="text-sm font-bold text-green-900 dark:text-green-100">Responded</span>
          </div>
          <button
            @click.stop="submitPermission(false)"
            :disabled="isSubmitting || hasSubmittedResponse"
            class="px-6 py-2 bg-red-600 hover:bg-red-700 text-white font-bold rounded-lg transition-all duration-200 shadow-md hover:shadow-lg transform hover:scale-105"
            :class="hasSubmittedResponse ? 'opacity-40 cursor-not-allowed' : ''"
          >
            {{ isSubmitting ? '⏳' : '❌ Deny' }}
          </button>
          <button
            @click.stop="submitPermission(true)"
            :disabled="isSubmitting || hasSubmittedResponse"
            class="px-6 py-2 bg-green-600 hover:bg-green-700 text-white font-bold rounded-lg transition-all duration-200 shadow-md hover:shadow-lg transform hover:scale-105"
            :class="hasSubmittedResponse ? 'opacity-40 cursor-not-allowed' : ''"
          >
            {{ isSubmitting ? '⏳' : '✅ Approve' }}
          </button>
        </div>
      </div>

      <div v-else-if="event.humanInTheLoop.type === 'choice'">
        <!-- Multiple Choice Buttons -->
        <div class="flex flex-wrap gap-2 justify-end">
          <button
            v-for="choice in event.humanInTheLoop.choices"
            :key="choice"
            @click.stop="submitChoice(choice)"
            :disabled="isSubmitting || hasSubmittedResponse"
            class="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-bold rounded-lg transition-all duration-200 shadow-md hover:shadow-lg transform hover:scale-105 disabled:transform-none"
          >
            {{ isSubmitting ? '⏳' : choice }}
          </button>
        </div>
      </div>
    </div>

    <!-- Original Event Row Content (skip if HITL with humanInTheLoop) -->
    <div
      v-if="!event.humanInTheLoop"
      class="event-row group relative cursor-pointer"
      :class="{ 'is-expanded': isExpanded }"
      @click="toggleExpanded"
    >
      <!-- accent bar -->
      <div class="accent-bar" :style="{ backgroundColor: appHexColor }"></div>

      <!-- main log line -->
      <div class="log-line">
        <!-- timestamp -->
        <span class="col-time">{{ formatTime(event.timestamp) }}</span>

        <!-- machine -->
        <span class="col-machine" :style="{ color: appHexColor }">{{ event.source_app }}</span>

        <!-- event type badge -->
        <span class="col-event" :class="eventTypeClass">{{ hookEmoji }} {{ event.hook_event_type }}</span>

        <!-- tool + detail -->
        <span class="col-detail">
          <span v-if="toolName" class="tool-name">{{ toolName }}</span>
          <span v-if="toolInfo?.detail" class="tool-detail">{{ toolInfo.detail }}</span>
          <span v-else-if="event.summary" class="tool-detail summary">{{ event.summary }}</span>
        </span>

        <!-- session id -->
        <span class="col-session">{{ sessionIdShort }}</span>

        <!-- expand chevron -->
        <span class="col-chevron" :class="{ rotated: isExpanded }">›</span>
      </div>

      <!-- expanded payload -->
      <div v-if="isExpanded" class="payload-panel" @click.stop>
        <div class="payload-header">
          <span class="payload-label">PAYLOAD</span>
          <button class="copy-btn" @click.stop="copyPayload">{{ copyButtonText }}</button>
        </div>
        <pre class="payload-pre">{{ formattedPayload }}</pre>
        <div v-if="event.chat && event.chat.length > 0" class="chat-btn-row">
          <button class="chat-btn" @click.stop="showChatModal = true">
            💬 Chat transcript ({{ event.chat.length }})
          </button>
        </div>
      </div>
    </div>
    <!-- Chat Modal -->
    <ChatTranscriptModal
      v-if="event.chat && event.chat.length > 0"
      :is-open="showChatModal"
      :chat="event.chat"
      @close="showChatModal = false"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import type { HookEvent, HumanInTheLoopResponse } from '../types';
import { useEventEmojis } from '../composables/useEventEmojis';
import ChatTranscriptModal from './ChatTranscriptModal.vue';
import { API_BASE_URL } from '../config';

const { getEmojiForToolName } = useEventEmojis();

const props = defineProps<{
  event: HookEvent;
  gradientClass: string;
  colorClass: string;
  appGradientClass: string;
  appColorClass: string;
  appHexColor: string;
}>();

const emit = defineEmits<{
  (e: 'response-submitted', response: HumanInTheLoopResponse): void;
}>();

// Existing refs
const isExpanded = ref(false);
const showChatModal = ref(false);
const copyButtonText = ref('📋 Copy');

// New refs for HITL
const responseText = ref('');
const isSubmitting = ref(false);
const hasSubmittedResponse = ref(false);
const localResponse = ref<HumanInTheLoopResponse | null>(null); // Optimistic UI

const toggleExpanded = () => {
  isExpanded.value = !isExpanded.value;
};

const sessionIdShort = computed(() => {
  return props.event.session_id.slice(0, 8);
});

const hookEmoji = computed(() => {
  const emojiMap: Record<string, string> = {
    'PreToolUse': '🔧',
    'PostToolUse': '✅',
    'PostToolUseFailure': '❌',
    'PermissionRequest': '🔐',
    'Notification': '🔔',
    'Stop': '🛑',
    'SubagentStart': '🟢',
    'SubagentStop': '👥',
    'PreCompact': '📦',
    'UserPromptSubmit': '💬',
    'SessionStart': '🚀',
    'SessionEnd': '🏁'
  };
  const baseEmoji = emojiMap[props.event.hook_event_type] || '❓';

  // For tool events, show combo: event emoji + tool emoji (e.g., 🔧💻)
  const toolEventTypes = ['PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'PermissionRequest'];
  if (toolEventTypes.includes(props.event.hook_event_type) && props.event.payload?.tool_name) {
    return `${baseEmoji}${getEmojiForToolName(props.event.payload.tool_name)}`;
  }

  return baseEmoji;
});

const borderColorClass = computed(() => {
  return props.colorClass.replace('bg-', 'border-');
});

const eventTypeClass = computed(() => {
  const t = props.event.hook_event_type;
  if (t === 'PreToolUse') return 'ev-pre';
  if (t === 'PostToolUse') return 'ev-post';
  if (t === 'PostToolUseFailure') return 'ev-fail';
  if (t === 'Stop' || t === 'SubagentStop') return 'ev-stop';
  if (t === 'SessionStart' || t === 'SessionEnd' || t === 'SubagentStart') return 'ev-session';
  if (t === 'UserPromptSubmit') return 'ev-prompt';
  return 'ev-other';
});


const appBorderStyle = computed(() => {
  return {
    borderColor: props.appHexColor
  };
});

const appBgStyle = computed(() => {
  // Use the hex color with 20% opacity
  return {
    backgroundColor: props.appHexColor + '33' // Add 33 for 20% opacity in hex
  };
});

const formattedPayload = computed(() => {
  return JSON.stringify(props.event.payload, null, 2);
});

const toolName = computed(() => {
  const eventType = props.event.hook_event_type;
  const toolEvents = ['PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'PermissionRequest'];
  if (toolEvents.includes(eventType) && props.event.payload?.tool_name) {
    return props.event.payload.tool_name;
  }
  return null;
});

const toolInfo = computed(() => {
  const payload = props.event.payload;
  
  // Handle UserPromptSubmit events
  if (props.event.hook_event_type === 'UserPromptSubmit' && payload.prompt) {
    return {
      tool: 'Prompt:',
      detail: `"${payload.prompt.slice(0, 100)}${payload.prompt.length > 100 ? '...' : ''}"`
    };
  }
  
  // Handle PreCompact events
  if (props.event.hook_event_type === 'PreCompact') {
    const trigger = payload.trigger || 'unknown';
    return {
      tool: 'Compaction:',
      detail: trigger === 'manual' ? 'Manual compaction' : 'Auto-compaction (full context)'
    };
  }
  
  // Handle SessionStart events
  if (props.event.hook_event_type === 'SessionStart') {
    const source = payload.source || 'unknown';
    const sourceLabels: Record<string, string> = {
      'startup': 'New session',
      'resume': 'Resuming session',
      'clear': 'Fresh session'
    };
    return {
      tool: 'Session:',
      detail: sourceLabels[source] || source
    };
  }
  
  // Handle tool-based events
  if (payload.tool_name) {
    const info: { tool: string; detail?: string } = { tool: payload.tool_name };
    
    if (payload.tool_input) {
      const input = payload.tool_input;
      if (input.command) {
        info.detail = input.command.slice(0, 50) + (input.command.length > 50 ? '...' : '');
      } else if (input.file_path) {
        info.detail = input.file_path.split('/').pop();
      } else if (input.pattern) {
        info.detail = input.pattern;
      } else if (input.url) {
        // WebFetch
        info.detail = input.url.slice(0, 60) + (input.url.length > 60 ? '...' : '');
      } else if (input.query) {
        // WebSearch
        info.detail = `"${input.query.slice(0, 50)}${input.query.length > 50 ? '...' : ''}"`;
      } else if (input.notebook_path) {
        // NotebookEdit
        info.detail = input.notebook_path.split('/').pop();
      } else if (input.recipient) {
        // SendMessage
        info.detail = `→ ${input.recipient}${input.summary ? ': ' + input.summary : ''}`;
      } else if (input.subject) {
        // TaskCreate
        info.detail = input.subject;
      } else if (input.taskId) {
        // TaskGet, TaskUpdate
        info.detail = `#${input.taskId}${input.status ? ' → ' + input.status : ''}`;
      } else if (input.description && input.subagent_type) {
        // Task (launch agent)
        info.detail = `${input.subagent_type}: ${input.description}`;
      } else if (input.task_id) {
        // TaskOutput, TaskStop
        info.detail = `task: ${input.task_id}`;
      } else if (input.team_name) {
        // TeamCreate
        info.detail = input.team_name;
      } else if (input.skill) {
        // Skill
        info.detail = input.skill;
      }
    }
    
    return info;
  }
  
  return null;
});

const formatTime = (timestamp?: number) => {
  if (!timestamp) return '';
  const date = new Date(timestamp);
  return date.toLocaleTimeString();
};

const copyPayload = async () => {
  try {
    await navigator.clipboard.writeText(formattedPayload.value);
    copyButtonText.value = '✅ Copied!';
    setTimeout(() => {
      copyButtonText.value = '📋 Copy';
    }, 2000);
  } catch (err) {
    console.error('Failed to copy:', err);
    copyButtonText.value = '❌ Failed';
    setTimeout(() => {
      copyButtonText.value = '📋 Copy';
    }, 2000);
  }
};

// New computed properties for HITL
const hitlTypeEmoji = computed(() => {
  if (!props.event.humanInTheLoop) return '';
  const emojiMap = {
    question: '❓',
    permission: '🔐',
    choice: '🎯'
  };
  return emojiMap[props.event.humanInTheLoop.type] || '❓';
});

const hitlTypeLabel = computed(() => {
  if (!props.event.humanInTheLoop) return '';
  const labelMap = {
    question: 'Agent Question',
    permission: 'Permission Request',
    choice: 'Choice Required'
  };
  return labelMap[props.event.humanInTheLoop.type] || 'Question';
});

const permissionType = computed(() => {
  return props.event.payload?.permission_type || null;
});

// Methods for HITL responses
const submitResponse = async () => {
  if (!responseText.value.trim() || !props.event.id) return;

  const response: HumanInTheLoopResponse = {
    response: responseText.value.trim(),
    hookEvent: props.event,
    respondedAt: Date.now()
  };

  // Optimistic UI: Show response immediately
  localResponse.value = response;
  hasSubmittedResponse.value = true;
  const savedText = responseText.value;
  responseText.value = '';
  isSubmitting.value = true;

  try {
    const res = await fetch(`${API_BASE_URL}/events/${props.event.id}/respond`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(response)
    });

    if (!res.ok) throw new Error('Failed to submit response');

    emit('response-submitted', response);
  } catch (error) {
    console.error('Error submitting response:', error);
    // Rollback optimistic update
    localResponse.value = null;
    hasSubmittedResponse.value = false;
    responseText.value = savedText;
    alert('Failed to submit response. Please try again.');
  } finally {
    isSubmitting.value = false;
  }
};

const submitPermission = async (approved: boolean) => {
  if (!props.event.id) return;

  const response: HumanInTheLoopResponse = {
    permission: approved,
    hookEvent: props.event,
    respondedAt: Date.now()
  };

  // Optimistic UI: Show response immediately
  localResponse.value = response;
  hasSubmittedResponse.value = true;
  isSubmitting.value = true;

  try {
    const res = await fetch(`${API_BASE_URL}/events/${props.event.id}/respond`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(response)
    });

    if (!res.ok) throw new Error('Failed to submit permission');

    emit('response-submitted', response);
  } catch (error) {
    console.error('Error submitting permission:', error);
    // Rollback optimistic update
    localResponse.value = null;
    hasSubmittedResponse.value = false;
    alert('Failed to submit permission. Please try again.');
  } finally {
    isSubmitting.value = false;
  }
};

const submitChoice = async (choice: string) => {
  if (!props.event.id) return;

  const response: HumanInTheLoopResponse = {
    choice,
    hookEvent: props.event,
    respondedAt: Date.now()
  };

  // Optimistic UI: Show response immediately
  localResponse.value = response;
  hasSubmittedResponse.value = true;
  isSubmitting.value = true;

  try {
    const res = await fetch(`${API_BASE_URL}/events/${props.event.id}/respond`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(response)
    });

    if (!res.ok) throw new Error('Failed to submit choice');

    emit('response-submitted', response);
  } catch (error) {
    console.error('Error submitting choice:', error);
    // Rollback optimistic update
    localResponse.value = null;
    hasSubmittedResponse.value = false;
    alert('Failed to submit choice. Please try again.');
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<style scoped>
@keyframes pulse-slow {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.95; }
}
.animate-pulse-slow { animation: pulse-slow 2s ease-in-out infinite; }

/* ── Terminal log row ── */
.event-row {
  position: relative;
  border-bottom: 1px solid rgba(255,255,255,0.04);
  transition: background 0.1s;
}
.event-row:hover { background: rgba(255,255,255,0.03); }
.event-row.is-expanded { background: rgba(255,255,255,0.05); }

.accent-bar {
  position: absolute;
  left: 0; top: 0; bottom: 0;
  width: 3px;
}

.log-line {
  display: grid;
  grid-template-columns: 80px 110px 180px 1fr 70px 18px;
  align-items: center;
  gap: 0 12px;
  padding: 7px 12px 7px 16px;
  font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', ui-monospace, monospace;
  font-size: 12px;
  line-height: 1.4;
  white-space: nowrap;
  overflow: hidden;
}

.col-time {
  color: #4a5568;
  font-size: 11px;
  letter-spacing: 0.02em;
  flex-shrink: 0;
}

.col-machine {
  font-weight: 700;
  font-size: 12px;
  letter-spacing: 0.03em;
  overflow: hidden;
  text-overflow: ellipsis;
}

.col-event {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  overflow: hidden;
  text-overflow: ellipsis;
}
.col-event.ev-pre    { color: #63b3ed; }
.col-event.ev-post   { color: #68d391; }
.col-event.ev-fail   { color: #fc8181; }
.col-event.ev-stop   { color: #f6ad55; }
.col-event.ev-session{ color: #b794f4; }
.col-event.ev-prompt { color: #76e4f7; }
.col-event.ev-other  { color: #a0aec0; }

.col-detail {
  display: flex;
  align-items: center;
  gap: 8px;
  overflow: hidden;
  min-width: 0;
}
.tool-name {
  color: #e2e8f0;
  font-weight: 600;
  flex-shrink: 0;
}
.tool-detail {
  color: #718096;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.tool-detail.summary { color: #a0aec0; font-style: italic; }

.col-session {
  color: #4a5568;
  font-size: 10px;
  text-align: right;
  letter-spacing: 0.05em;
}

.col-chevron {
  color: #4a5568;
  font-size: 16px;
  line-height: 1;
  transition: transform 0.15s;
  text-align: center;
}
.col-chevron.rotated { transform: rotate(90deg); color: #a0aec0; }

/* ── Expanded payload ── */
.payload-panel {
  border-top: 1px solid rgba(255,255,255,0.06);
  padding: 10px 16px 12px 16px;
  background: rgba(0,0,0,0.25);
}
.payload-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}
.payload-label {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.12em;
  color: #4a5568;
}
.copy-btn {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: #63b3ed;
  background: none;
  border: 1px solid #2d3748;
  border-radius: 3px;
  padding: 2px 8px;
  cursor: pointer;
  transition: border-color 0.15s, color 0.15s;
}
.copy-btn:hover { border-color: #63b3ed; color: #90cdf4; }

.payload-pre {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: #a0aec0;
  background: rgba(0,0,0,0.3);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 4px;
  padding: 10px 12px;
  overflow-x: auto;
  max-height: 240px;
  overflow-y: auto;
  line-height: 1.6;
}

.chat-btn-row { margin-top: 8px; display: flex; justify-content: flex-end; }
.chat-btn {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  color: #b794f4;
  background: none;
  border: 1px solid #44337a;
  border-radius: 3px;
  padding: 3px 10px;
  cursor: pointer;
  transition: border-color 0.15s;
}
.chat-btn:hover { border-color: #b794f4; }
</style>