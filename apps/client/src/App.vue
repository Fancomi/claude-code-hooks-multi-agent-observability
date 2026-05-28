<template>
  <div class="h-screen flex flex-col bg-[#070a0f]">
    <EventTimeline
      :events="events"
      :filters="filters"
      :is-connected="isConnected"
      v-model:stick-to-bottom="stickToBottom"
    />

    <div
      v-if="error"
      class="fixed bottom-4 left-4 bg-red-950/90 border border-red-500/40 text-red-100 px-3 py-2 rounded-lg text-sm shadow-xl"
    >
      连接异常：{{ error }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { useWebSocket } from './composables/useWebSocket';
import EventTimeline from './components/EventTimeline.vue';
import { WS_URL } from './config';

const { events, isConnected, error } = useWebSocket(WS_URL);

const filters = ref({
  sourceApp: '',
  sessionId: '',
  eventType: ''
});

const stickToBottom = ref(true);
</script>