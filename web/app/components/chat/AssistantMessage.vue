<template>
  <v-card class="assistant-message" variant="flat" rounded="lg">
    <v-card-text class="pa-4">
      <ToolCallList v-if="props.message.tool_calls.length > 0" :tool-calls="props.message.tool_calls"
                    class="mb-2" @open="(t) => emit('open-tool-call', t)"/>

      <template v-if="props.message.content">
        <MarkdownContent :content="content" class="text-body-1"/>
        <TypingDots v-if="generating || revealing" class="text-medium-emphasis mt-4"/>
      </template>

      <div v-else-if="generating" class="d-flex align-center text-medium-emphasis">
        <TypingDots class="mr-2"/>
        {{ $t('chat.assistantMessage.thinking') }}
      </div>

      <p v-else-if="props.message.status === MessageStatus.COMPLETED && presentedFiles.length === 0
                    && changes.length === 0"
         class="text-medium-emphasis">
        {{ $t('chat.assistantMessage.noAnswer') }}
      </p>

      <div v-if="presentedFiles.length > 0 || changes.length > 0" class="d-flex flex-wrap ga-2 mt-6">
        <v-btn v-for="change in changes" :key="change.toolCall.id" variant="tonal" size="large" class="text-none"
               color="primary" :prepend-icon="CHANGE_ICONS[change.toolCall.name]" :text="changeLabel(change)"
               :title="changeTitle(change)" @click="emit('open-file', change.toolCall)"/>
        <v-btn v-for="file in presentedFiles" :key="file.toolCall.id" variant="tonal" size="large" class="text-none"
               prepend-icon="mdi-file-document-outline" :text="fileName(file.path)" :title="file.path"
               @click="emit('open-file', file.toolCall)"/>
      </div>

      <v-alert v-if="props.message.status === MessageStatus.FAILED" type="error" variant="tonal" density="compact"
               class="mt-3" :text="props.message.error ?? $t('chat.assistantMessage.failed')"/>

      <div v-if="props.message.status === MessageStatus.CANCELLED" class="text-caption text-medium-emphasis mt-3">
        <IconText icon="mdi-cancel">{{ $t('chat.assistantMessage.cancelled') }}</IconText>
      </div>

      <!-- On mobile one line that never wraps: the model on the left (cut off when too long), the duration and the cost
           on the right. Otherwise all of it on the left. -->
      <div v-if="props.modelName || duration || cost"
           class="footer d-flex align-center text-caption text-medium-emphasis mt-3"
           :class="{'flex-wrap': !display.xs.value}">
        <IconText v-if="props.modelName" icon="mdi-robot-outline" class="footer-model" :title="props.modelName">
          <span :class="{'text-truncate': display.xs.value}">{{ props.modelName }}</span>
        </IconText>
        <span v-if="props.modelName && !display.xs.value && (duration || cost)" class="mx-2">·</span>
        <span class="d-flex align-center flex-shrink-0" :class="{'ms-auto ps-3': display.xs.value}">
          <span v-if="duration" class="tabular">{{ duration }}</span>
          <span v-if="duration && cost" class="mx-2">·</span>
          <button v-if="cost" type="button" class="usage-link tabular" :title="$t('chat.assistantMessage.showUsage')"
                  @click="emit('open-usage')">
            {{ cost }}
          </button>
        </span>
      </div>

      <v-btn v-if="props.canRetry" class="mt-3" size="small" variant="tonal" prepend-icon="mdi-refresh"
             :text="$t('common.retry')" :loading="props.retrying" @click="emit('retry')"/>
    </v-card-text>
  </v-card>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, ref, watch} from "vue";
import {useI18n} from "#i18n";
import {useDisplay} from "vuetify";
import {MessageStatus, type MessageDto, type ToolCallSummaryDto} from "~/utils/model";
import {
  CHANGE_ICONS,
  fileName,
  formatCost,
  presentedFiles as presentedFilesOf,
  proposedChanges,
  toolCallMoves,
} from "~/utils/utils";
import MarkdownContent from "~/components/chat/MarkdownContent.vue";
import ToolCallList from "~/components/chat/ToolCallList.vue";
import IconText from "~/components/IconText.vue";
import TypingDots from "~/components/chat/TypingDots.vue";
import {useSmoothText} from "~/composables/smoothText";

const {t} = useI18n();
const display = useDisplay();

const props = defineProps<{
  message: MessageDto,
  /** The model that wrote the answer, if it still exists. */
  modelName?: string,
  /** Only the last answer can be retried, and only if it failed or was cancelled. */
  canRetry: boolean,
  retrying: boolean,
}>();

const emit = defineEmits<{
  (e: 'retry'): void,
  (e: 'open-tool-call', toolCall: ToolCallSummaryDto): void,
  (e: 'open-usage'): void,
  /** A `present_file_to_user`, `change_file`, `move_files` or `save_attachment` call. */
  (e: 'open-file', toolCall: ToolCallSummaryDto): void,
}>();

const generating = computed(() => props.message.status === MessageStatus.GENERATING);

/** Streamed text is revealed smoothly rather than in the batches it arrives in. */
const {text: content, revealing} = useSmoothText(() => props.message.content);

/** Shown only once the answer is complete, not while generating or after it failed or was cancelled. */
const presentedFiles = computed(() =>
    props.message.status === MessageStatus.COMPLETED ? presentedFilesOf(props.message) : []);

/** Shown like the files. */
const changes = computed(() =>
    props.message.status === MessageStatus.COMPLETED ? proposedChanges(props.message) : []);

type Change = ReturnType<typeof proposedChanges>[number];

/** The file it changes, or what it moves. */
const changeLabel = (change: Change) => {
  const moves = toolCallMoves(change.toolCall);
  return moves.length > 1 ? t('chat.moveCount', moves.length) : fileName(change.path);
};

const changeTitle = (change: Change) => {
  switch (change.toolCall.name) {
    case 'save_attachment':
      return t('chat.assistantMessage.proposedStore', {path: change.path});
    case 'move_files': {
      const moves = toolCallMoves(change.toolCall).map(m => `${m.from} → ${m.to}`).join(', ');
      return t('chat.assistantMessage.proposedMoves', {moves});
    }
    default:
      return t('chat.assistantMessage.proposedChange', {path: change.path});
  }
};

/** Ticks every second while generating, so the duration counts up. */
const now = ref(Date.now());
let timer: ReturnType<typeof setInterval> | null = null;

watch(generating, (value) => {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
  if (value) {
    now.value = Date.now();
    timer = setInterval(() => now.value = Date.now(), 1000);
  }
}, {immediate: true});

onBeforeUnmount(() => {
  if (timer) {
    clearInterval(timer);
  }
});

/** How long the answer took (or has taken so far), unknown if it was interrupted by a restart. */
const duration = computed(() => {
  const end = generating.value ? now.value : props.message.finished_at ? Date.parse(props.message.finished_at) : null;
  if (end === null) {
    return null;
  }
  // clamped, as the client clock may be behind the server's
  const seconds = Math.max(0, Math.floor((end - Date.parse(props.message.created_at)) / 1000));
  return seconds < 60 ? t('chat.assistantMessage.durationSeconds', {seconds})
      : t('chat.assistantMessage.durationMinutes',
          {minutes: Math.floor(seconds / 60), seconds: String(seconds % 60).padStart(2, '0')});
});

// A cost is only computed from a usage, so an answer with one always has the other.
const cost = computed(() => props.message.cost && props.message.usage ? formatCost(props.message.cost.amount, props.message.cost.currency) : null);

</script>

<style scoped>
.tabular {
  font-variant-numeric: tabular-nums;
}

.footer {
  letter-spacing: 0.2px !important;
}

.footer-model {
  min-width: 0;
}

.usage-link {
  padding: 0;
  border: 0;
  background: none;
  font: inherit;
  color: inherit;
  cursor: pointer;
}

.usage-link:hover {
  color: rgb(var(--v-theme-on-surface));
}
</style>
