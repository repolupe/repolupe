<template>
  <v-dialog v-model="dialog" max-width="480">
    <v-card v-if="props.message && totalMs !== null">
      <v-card-title class="pt-4">{{ $t('chat.durationDialog.title') }}</v-card-title>
      <v-card-subtitle v-if="props.message.model_name" class="pb-2">
        <IconText icon="mdi-robot-outline">{{ props.message.model_name }}</IconText>
      </v-card-subtitle>

      <v-card-text>
        <v-table density="compact">
          <tbody v-if="responseMs !== null">
          <tr>
            <td>
              {{ $t('chat.durationDialog.model') }}
            </td>
            <td class="text-right tabular text-no-wrap">{{ formatDuration(responseMs) }}</td>
          </tr>
          <tr v-if="speed !== null">
            <td>
              {{ $t('chat.durationDialog.speed') }}
            </td>
            <td class="text-right tabular text-no-wrap">
              {{ $t('chat.durationDialog.tokensPerSecond', {speed: formatSpeed(speed)}) }}
            </td>
          </tr>
          </tbody>
          <tbody v-if="tools.length">
          <tr>
            <td colspan="2" class="section-title text-subtitle-2">{{ $t('chat.durationDialog.tools') }}</td>
          </tr>
          <tr v-for="tool in tools" :key="tool.name">
            <td>
              <div class="tool-label">
                <span class="text-medium-emphasis tabular">
                  {{ $t('chat.durationDialog.callCount', {count: tool.count}) }}
                </span>
                <span class="tool-name">{{ tool.label }}</span>
                <span v-if="tool.server" class="tool-server">{{ tool.server }}</span>
              </div>
            </td>
            <td class="text-right tabular text-no-wrap">{{ formatDuration(tool.ms) }}</td>
          </tr>
          <tr>
            <td>
              {{ $t('chat.durationDialog.toolsSum') }}
            </td>
            <td class="text-right tabular text-no-wrap">{{ formatDuration(toolsSumMs) }}</td>
          </tr>
          <tr>
            <td>
              {{ $t('chat.durationDialog.toolsReal') }}
              <div class="text-caption text-medium-emphasis">{{ $t('chat.durationDialog.toolsRealHint') }}</div>
            </td>
            <td class="text-right tabular text-no-wrap">{{ formatDuration(toolsRealMs) }}</td>
          </tr>
          </tbody>
          <tfoot>
          <tr class="font-weight-medium">
            <td>{{ $t('chat.durationDialog.total') }}</td>
            <td class="text-right tabular text-no-wrap">{{ formatDuration(totalMs) }}</td>
          </tr>
          </tfoot>
        </v-table>

        <p v-if="responseMs === null && !generating" class="text-caption text-medium-emphasis mt-3">
          {{ $t('chat.durationDialog.notMeasured') }}
        </p>
      </v-card-text>

      <v-card-actions>
        <v-spacer/>
        <v-btn :text="$t('common.close')" @click="dialog = false"/>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, ref, watch} from "vue";
import {useI18n} from "#i18n";
import {MessageStatus, type MessageDto} from "~/utils/model";
import {formatLocale} from "~/utils/i18n";
import {parseMcpToolName} from "~/utils/utils";
import IconText from "~/components/IconText.vue";

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  /** Passed in rather than loaded, so the times keep up while the answer is generating. */
  message: MessageDto | null,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const generating = computed(() => props.message?.status === MessageStatus.GENERATING);

/** Ticks while open and generating, so the total runs like a stopwatch. */
const now = ref(Date.now());
let timer: ReturnType<typeof setInterval> | null = null;

watch(() => props.modelValue && generating.value, (value) => {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
  if (value) {
    now.value = Date.now();
    timer = setInterval(() => now.value = Date.now(), 100);
  }
}, {immediate: true});

onBeforeUnmount(() => {
  if (timer) {
    clearInterval(timer);
  }
});

/** Like the duration below the answer, unknown if it was interrupted by a restart. */
const totalMs = computed(() => {
  const message = props.message;
  if (!message) {
    return null;
  }
  const end = generating.value ? now.value : message.finished_at ? Date.parse(message.finished_at) : null;
  // clamped, as the client clock may be behind the server's
  return end === null ? null : Math.max(0, end - Date.parse(message.created_at));
});

/** `null` if unknown. */
const responseMs = computed(() => props.message?.response_ms ?? null);

/** Output tokens per second of the responses so far, `null` before the first. */
const speed = computed(() => {
  const outputTokens = props.message?.usage?.output_tokens;
  if (outputTokens === undefined || !responseMs.value) {
    return null;
  }
  return outputTokens / (responseMs.value / 1000);
});

interface ToolDuration {
  /** The full name, e.g. `mcp__github__search`. */
  name: string,
  /** As shown: an MCP tool without its server. */
  label: string,
  server: string | null,
  count: number,
  ms: number,
}

/** The finished calls grouped by tool, the longest first, then the most called. Running ones join once they finish. */
const tools = computed((): ToolDuration[] => {
  const byName = new Map<string, ToolDuration>();
  for (const toolCall of props.message?.tool_calls ?? []) {
    if (toolCall.duration_ms === null) {
      continue;
    }
    let tool = byName.get(toolCall.name);
    if (!tool) {
      const mcp = parseMcpToolName(toolCall.name);
      tool = {name: toolCall.name, label: mcp?.tool ?? toolCall.name, server: mcp?.server ?? null, count: 0, ms: 0};
      byName.set(toolCall.name, tool);
    }
    tool.count++;
    tool.ms += toolCall.duration_ms;
  }
  return [...byName.values()].sort((a, b) => b.ms - a.ms || b.count - a.count || a.name.localeCompare(b.name));
});

/** Can be more than the time the tools took, as calls of the same response run at the same time. */
const toolsSumMs = computed(() => tools.value.reduce((sum, tool) => sum + tool.ms, 0));

/**
 * How long at least one tool was running: the union of the finished calls' runs. A call starts right after it was
 * created, the server only stores the other calls of the same response in between.
 */
const toolsRealMs = computed(() => {
  const runs = (props.message?.tool_calls ?? [])
      .flatMap(t => t.duration_ms === null ? [] : [{start: Date.parse(t.created_at), ms: t.duration_ms}])
      .sort((a, b) => a.start - b.start);
  let total = 0;
  let coveredUntil = -Infinity;
  for (const run of runs) {
    const end = run.start + run.ms;
    total += Math.max(0, end - Math.max(run.start, coveredUntil));
    coveredUntil = Math.max(coveredUntil, end);
  }
  return total;
});

/**
 * With tenths of a second below a minute, e.g. "12.3s" or "<0.1s", and else whole seconds, e.g. "2m 05s". Rounded
 * down like the duration below the answer, so the total matches it.
 */
const formatDuration = (ms: number) => {
  if (ms < 100) {
    return t('chat.durationDialog.lessThan', {duration: formatSeconds(0.1)});
  }
  if (ms < 60_000) {
    return formatSeconds(Math.floor(ms / 100) / 10);
  }
  const seconds = Math.floor(ms / 1000);
  return t('chat.assistantMessage.durationMinutes',
      {minutes: Math.floor(seconds / 60), seconds: String(seconds % 60).padStart(2, '0')});
};

const formatSeconds = (seconds: number) => t('chat.assistantMessage.durationSeconds', {
  seconds: new Intl.NumberFormat(formatLocale(), {minimumFractionDigits: 1, maximumFractionDigits: 1}).format(seconds),
});

const formatSpeed = (value: number) => value.toLocaleString(formatLocale(), {maximumFractionDigits: 1});
</script>

<style scoped>
.tabular {
  font-variant-numeric: tabular-nums;
}

.section-title {
  padding-top: 12px !important;
  vertical-align: bottom;
}

/* wraps between its parts, which have no spaces between them to break at */
.tool-label {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  column-gap: 8px;
  min-width: 0;
}

.tool-name, .tool-server {
  overflow-wrap: anywhere;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.8rem;
}

.tool-name {
  font-weight: 600;
}

.tool-server {
  opacity: 0.75;
}
</style>
