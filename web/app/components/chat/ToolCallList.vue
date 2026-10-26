<template>
  <div class="tool-call-list">
    <v-btn variant="text" size="small" class="px-2 text-none text-medium-emphasis" @click="expanded = !expanded"
           :append-icon="expanded ? 'mdi-chevron-up' : 'mdi-chevron-down'">
      <v-progress-circular v-if="running" indeterminate size="14" width="2" class="mr-2"/>
      <v-icon v-else icon="mdi-tools" size="16" class="mr-2"/>
      {{ summary }}
    </v-btn>

    <v-expand-transition>
      <div v-show="expanded" class="tool-call-rows mt-1">
        <div v-for="toolCall in props.toolCalls" :key="toolCall.id" class="tool-call-row" v-ripple
             role="button" tabindex="0" @click="emit('open', toolCall)" @keydown.enter="emit('open', toolCall)">
          <ToolCallLabel :tool-call="toolCall" class="flex-grow-1"/>
          <ToolCallStatusIcon :status="toolCall.status" class="ml-2 flex-shrink-0"/>
        </div>
      </div>
    </v-expand-transition>
  </div>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {ToolCallStatus, type ToolCallSummaryDto} from "~/utils/model";
import ToolCallLabel from "~/components/chat/ToolCallLabel.vue";
import ToolCallStatusIcon from "~/components/chat/ToolCallStatusIcon.vue";

const {t} = useI18n();

const props = defineProps<{
  toolCalls: ToolCallSummaryDto[],
}>();

const emit = defineEmits<{
  (e: 'open', toolCall: ToolCallSummaryDto): void,
}>();

/** Collapsed until the user opens it, also while the answer is generating. */
const expanded = ref(false);

const running = computed(() => props.toolCalls.some(t => t.status === ToolCallStatus.RUNNING));

const summary = computed(() => {
  const count = props.toolCalls.length;
  const failed = props.toolCalls.filter(t => t.status === ToolCallStatus.FAILED).length;
  if (running.value) {
    return t('chat.toolCallList.running');
  }
  return failed > 0 ? t('chat.toolCallList.usedWithFailed', {count, failed}, count) : t('chat.toolCallList.used', count);
});
</script>

<style scoped>
.tool-call-rows {
  border-left: 2px solid rgba(var(--v-theme-on-surface), 0.1);
  margin-left: 14px;
  padding-left: 8px;
}

.tool-call-row {
  display: flex;
  align-items: center;
  padding: 4px 8px;
  border-radius: 6px;
  cursor: pointer;
  min-width: 0;
}

.tool-call-row:hover,
.tool-call-row:focus-visible {
  background: rgba(var(--v-theme-on-surface), 0.05);
  outline: none;
}
</style>
