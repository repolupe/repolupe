<template>
  <span class="tool-call-label">
    <v-icon :icon="icon" size="16" class="mr-2"/>
    <span class="tool-call-name">{{ props.toolCall.name }}</span>
    <span v-if="detail" class="tool-call-detail ml-2">{{ detail }}</span>
  </span>
</template>

<script setup lang="ts">
import {computed} from "vue";
import {useI18n} from "#i18n";
import type {ToolCallSummaryDto} from "~/utils/model";
import {toolCallMoves} from "~/utils/utils";

const {t} = useI18n();

const props = defineProps<{
  toolCall: ToolCallSummaryDto,
}>();

const ICONS: Record<string, string> = {
  list_files: 'mdi-folder-outline',
  read_file: 'mdi-file-document-outline',
  grep: 'mdi-text-search',
  outline: 'mdi-format-list-bulleted-type',
  present_file_to_user: 'mdi-file-eye-outline',
  change_file: 'mdi-pencil-outline',
  move_files: 'mdi-file-move-outline',
  save_attachment: 'mdi-paperclip',
  read_attachment: 'mdi-paperclip',
  run_script: 'mdi-calculator-variant-outline',
};

const icon = computed(() => ICONS[props.toolCall.name] ?? 'mdi-wrench-outline');

const str = (value: unknown): string | null => {
  if (typeof value === 'string' && value) {
    return value;
  }
  if (typeof value === 'number') {
    return String(value);
  }
  return null;
};

/** The most telling part of the input, e.g. the path that was read or the pattern that was searched. */
const detail = computed(() => {
  const input = props.toolCall.input ?? {};
  const path = str(input.path);
  const glob = str(input.glob);
  switch (props.toolCall.name) {
    case 'list_files':
      return [path ?? '/', glob].filter(Boolean).join(' ');
    case 'read_file':
    case 'outline':
    case 'present_file_to_user':
    case 'change_file':
      return path ?? '';
    case 'move_files': {
      const moves = toolCallMoves(props.toolCall);
      return moves.length === 1 ? `${moves[0]!.from} → ${moves[0]!.to}` : t('chat.moveCount', moves.length);
    }
    case 'read_attachment': {
      const attachment = str(input.attachment);
      return attachment ? `#${attachment}` : '';
    }
    case 'save_attachment': {
      const attachment = str(input.attachment);
      return [attachment ? `#${attachment}` : null, path ? `→ ${path}` : null].filter(Boolean).join(' ');
    }
    case 'run_script': {
      const code = str(input.code);
      return code?.split('\n').map(line => line.trim()).find(Boolean) ?? '';
    }
    case 'grep': {
      const pattern = str(input.pattern);
      const where = [path, glob].filter(Boolean).join(' ');
      if (pattern && where) {
        return t('chat.toolCallLabel.grepPatternIn', {pattern, where});
      }
      return pattern ? `"${pattern}"` : where ? t('chat.toolCallLabel.grepIn', {where}) : '';
    }
    default: {
      const json = JSON.stringify(input);
      return json === '{}' ? '' : json;
    }
  }
});
</script>

<style scoped>
.tool-call-label {
  display: inline-flex;
  align-items: center;
  min-width: 0;
  max-width: 100%;
}

.tool-call-name {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.8rem;
  font-weight: 600;
  white-space: nowrap;
}

.tool-call-detail {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.8rem;
  opacity: 0.75;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  min-width: 0;
}
</style>
