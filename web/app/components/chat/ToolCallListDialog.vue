<template>
  <v-dialog v-model="dialog" max-width="720" scrollable>
    <v-card>
      <v-card-title class="pt-4">{{ $t('chat.assistantMessage.toolCount', props.toolCalls.length) }}</v-card-title>

      <v-card-text class="px-4">
        <div v-for="toolCall in props.toolCalls" :key="toolCall.id" class="tool-call-row" v-ripple
             role="button" tabindex="0" @click="emit('open', toolCall)" @keydown.enter="emit('open', toolCall)">
          <ToolCallLabel :tool-call="toolCall" class="flex-grow-1"/>
          <ToolCallStatusIcon :status="toolCall.status" class="ml-2 flex-shrink-0"/>
        </div>
      </v-card-text>

      <v-card-actions>
        <v-spacer/>
        <v-btn :text="$t('common.close')" @click="dialog = false"/>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed} from "vue";
import type {ToolCallSummaryDto} from "~/utils/model";
import ToolCallLabel from "~/components/chat/ToolCallLabel.vue";
import ToolCallStatusIcon from "~/components/chat/ToolCallStatusIcon.vue";

const props = defineProps<{
  modelValue: boolean,
  /** Passed in rather than loaded, so the list keeps up while the answer is generating. */
  toolCalls: ToolCallSummaryDto[],
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'open', toolCall: ToolCallSummaryDto): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});
</script>

<style scoped>
.tool-call-row {
  display: flex;
  align-items: center;
  padding: 6px 8px;
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
