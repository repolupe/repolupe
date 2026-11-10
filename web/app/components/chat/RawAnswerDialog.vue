<template>
  <v-dialog v-model="dialog" max-width="900" scrollable>
    <v-card>
      <v-card-title class="pt-4">{{ $t('chat.rawAnswerDialog.title') }}</v-card-title>

      <v-progress-linear v-if="fetching" indeterminate color="primary"/>

      <!-- the only scroll area: blocks wrap and grow instead of scrolling on their own -->
      <v-card-text>
        <p v-if="notAvailable" class="text-medium-emphasis">{{ $t('chat.rawAnswerDialog.notAvailable') }}</p>

        <!-- nesting is shown by the line on the left of each group, colored by who it comes from -->
        <div v-if="raw" class="raw-stack">
          <!-- the same in every answer, so hidden with the tools until asked for -->
          <section class="raw-group raw-system">
            <div class="raw-heading d-flex align-center">
              <span>{{ $t('chat.rawAnswerDialog.systemPrompt') }}</span>
              <v-btn variant="text" size="x-small" class="ml-2"
                     :text="showSystem ? $t('chat.rawAnswerDialog.hide') : $t('chat.rawAnswerDialog.show')"
                     @click="showSystem = !showSystem"/>
            </div>
            <pre v-if="showSystem" class="raw-block">{{ raw.system }}</pre>
          </section>

          <section v-if="showSystem && raw.tools.length > 0" class="raw-group raw-system">
            <div class="raw-heading">{{ $t('chat.rawAnswerDialog.tools') }} ({{ raw.tools.length }})</div>
            <div v-for="tool in raw.tools" :key="tool.name" class="raw-sub">
              <div class="raw-heading"><code>{{ tool.name }}</code></div>
              <pre class="raw-block">{{ tool.description }}</pre>
              <pre class="raw-block">{{ formatJson(tool.input_schema) }}</pre>
            </div>
          </section>

          <p class="text-overline mt-2">{{ $t('chat.rawAnswerDialog.messages') }}</p>

          <section v-for="(message, i) in raw.messages" :key="i" class="raw-group"
                   :class="message.role === MessageRole.USER ? 'raw-user' : 'raw-assistant'">
            <div class="raw-heading">{{ messageHeading(message) }}</div>
            <template v-for="(block, j) in message.content" :key="j">
              <pre v-if="block.type === 'TEXT'" class="raw-block">{{ block.text }}</pre>

              <div v-else-if="block.type === 'REASONING'" class="raw-sub">
                <div class="raw-label">
                  <IconText icon="mdi-head-lightbulb-outline">{{ $t('chat.rawAnswerDialog.reasoning') }}</IconText>
                </div>
                <pre v-if="block.text" class="raw-block font-italic">{{ block.text }}</pre>
                <p v-else class="text-body-2 text-medium-emphasis">
                  {{ $t('chat.rawAnswerDialog.reasoningWithheld') }}
                </p>
              </div>

              <div v-else-if="block.type === 'TOOL_USE'" class="raw-sub">
                <div class="raw-label">
                  <IconText icon="mdi-wrench-outline">{{ $t('chat.rawAnswerDialog.toolUse') }}: {{ block.id }}</IconText>
                </div>
                <pre class="raw-block">{{ block.name }}</pre>
                <pre class="raw-block">{{ formatJson(block.input) }}</pre>
              </div>

              <div v-else-if="block.type === 'TOOL_RESULT'" class="raw-sub">
                <div class="raw-label">
                  <!-- under a "Tool result" heading the id is enough -->
                  <IconText v-if="!onlyToolResults(message)" icon="mdi-keyboard-return" class="mr-2">
                    {{ $t('chat.rawAnswerDialog.toolResult') }}
                  </IconText>
                  <span>{{ toolResultLabel(block.tool_use_id) }}</span>
                  <v-chip v-if="block.is_error" color="error" size="x-small" variant="tonal" class="ml-2"
                          :text="$t('chat.rawAnswerDialog.error')"/>
                </div>
                <pre class="raw-block">{{ block.content }}</pre>
              </div>
            </template>
          </section>
        </div>
      </v-card-text>

      <v-card-actions>
        <v-btn v-if="raw" prepend-icon="mdi-content-copy" :text="$t('chat.rawAnswerDialog.copy')" @click="doCopy"/>
        <v-spacer/>
        <v-btn :text="$t('common.close')" @click="dialog = false"/>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {ErrorCode, MessageRole, type MessageDto, type RawAnswerDto, type RawMessageDto} from "~/utils/model";
import {ApiError, errorMessage, getRawAnswer} from "~/utils/api";
import {showSnackbar} from "~/utils/utils";
import IconText from "~/components/IconText.vue";

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  chatId: string,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const messageId = ref<string | null>(null);
const raw = ref<RawAnswerDto | null>(null);
/** Answers interrupted by a restart have none. */
const notAvailable = ref(false);
const fetching = ref(false);
const showSystem = ref(false);

/** Arguments that were not a JSON object are a string, shown as the model sent them. */
const formatJson = (value: unknown) => typeof value === 'string' ? value : JSON.stringify(value, null, 2);

/** Tool results are sent as user messages, but don't come from the user. */
const onlyToolResults = (message: RawMessageDto) =>
    message.content.length > 0 && message.content.every(b => b.type === 'TOOL_RESULT');

const messageHeading = (message: RawMessageDto) => {
  if (message.role === MessageRole.ASSISTANT) {
    return t('chat.rawAnswerDialog.assistant');
  }
  return onlyToolResults(message) ? t('chat.rawAnswerDialog.toolResult') : t('chat.rawAnswerDialog.user');
};

/** The tool of each call, by the call's id, since a result only has the id. */
const toolNames = computed(() => {
  const names = new Map<string, string>();
  for (const message of raw.value?.messages ?? []) {
    for (const block of message.content) {
      if (block.type === 'TOOL_USE') {
        names.set(block.id, block.name);
      }
    }
  }
  return names;
});

const toolResultLabel = (toolUseId: string) => {
  const name = toolNames.value.get(toolUseId);
  return name ? `${name} (${toolUseId})` : toolUseId;
};

const fetchRaw = async () => {
  const id = messageId.value;
  if (!id) {
    return;
  }
  fetching.value = true;
  try {
    const result = await getRawAnswer(props.chatId, id);
    if (messageId.value === id) {
      raw.value = result;
    }
  } catch (e) {
    if (messageId.value !== id) {
      return;
    }
    if (e instanceof ApiError && e.code === ErrorCode.NOT_FOUND) {
      notAvailable.value = true;
    } else {
      showSnackbar(t('chat.rawAnswerDialog.loadFailed', {error: errorMessage(e)}));
    }
  } finally {
    if (messageId.value === id) {
      fetching.value = false;
    }
  }
};

const doCopy = async () => {
  try {
    await navigator.clipboard.writeText(JSON.stringify(raw.value, null, 2));
    showSnackbar(t('chat.rawAnswerDialog.copied'));
  } catch {
    showSnackbar(t('chat.rawAnswerDialog.copyFailed'));
  }
};

defineExpose({
  load: (message: MessageDto) => {
    messageId.value = message.id;
    raw.value = null;
    notAvailable.value = false;
    showSystem.value = false;
    fetchRaw();
  },
});
</script>

<style scoped>
.raw-stack {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.raw-group {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 0;
  padding-left: 12px;
  border-left: 3px solid var(--raw-line);
}

/* A part of a group, e.g. a tool or a tool call, set apart by its heading rather than a line */
.raw-sub {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 0;
}

.raw-sub + .raw-sub {
  margin-top: 8px;
}

/* Mid tones, visible on the light and the dark surface */
.raw-system {
  --raw-line: #fb8c00;
}

.raw-user {
  --raw-line: #42a5f5;
}

.raw-assistant {
  --raw-line: #ab47bc;
}

.raw-heading {
  font-size: 0.875rem;
  font-weight: 500;
  overflow-wrap: anywhere;
}

.raw-label {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  font-size: 0.75rem;
  color: rgba(var(--v-theme-on-surface), var(--v-medium-emphasis-opacity));
  overflow-wrap: anywhere;
}

/* Everything wraps, JSON too, so nothing scrolls sideways */
.raw-block {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.8rem;
  line-height: 1.5;
  background: rgba(var(--v-theme-on-surface), 0.05);
  border-radius: 6px;
  padding: 10px 12px;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
</style>
