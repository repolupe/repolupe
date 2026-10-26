<template>
  <v-dialog v-model="dialog" max-width="900" scrollable>
    <v-card v-if="summary">
      <v-card-title class="d-flex align-center pt-4">
        <ToolCallLabel :tool-call="summary" class="flex-grow-1"/>
        <ToolCallStatusIcon :status="toolCall?.status ?? summary.status" class="ml-2 flex-shrink-0"/>
      </v-card-title>

      <v-card-subtitle class="pb-2">
        <IconText v-if="repositoryName" icon="mdi-source-repository">{{ repositoryName }}</IconText>
        <IconText v-if="summary.commit_sha" icon="mdi-source-commit" class="ml-3" :title="summary.commit_sha">
          <code>{{ shortSha(summary.commit_sha) }}</code>
        </IconText>
        <span class="ml-3">{{ formatDateTime(summary.created_at) }}</span>
      </v-card-subtitle>

      <v-progress-linear v-if="fetching" indeterminate color="primary"/>

      <v-card-text>
        <p class="text-overline">{{ $t('common.input') }}</p>
        <pre class="tool-call-block">{{ inputJson }}</pre>

        <p class="text-overline mt-4">{{ $t('common.output') }}</p>
        <pre v-if="toolCall?.output" class="tool-call-block tool-call-output">{{ toolCall.output }}</pre>
        <p v-else-if="toolCall && toolCall.status === ToolCallStatus.RUNNING" class="text-medium-emphasis">
          {{ $t('chat.toolCallDialog.stillRunning') }}
        </p>
        <p v-else-if="!fetching" class="text-medium-emphasis">{{ $t('chat.toolCallDialog.noOutput') }}</p>
      </v-card-text>

      <v-card-actions>
        <v-btn v-if="toolCall?.status === ToolCallStatus.RUNNING" :text="$t('common.refresh')"
               prepend-icon="mdi-refresh" :loading="fetching" @click="fetchToolCall"/>
        <v-spacer/>
        <v-btn :text="$t('common.close')" @click="dialog = false"/>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {ToolCallStatus, type RepositoryDto, type ToolCallDto, type ToolCallSummaryDto} from "~/utils/model";
import {errorMessage, getToolCall} from "~/utils/api";
import {formatDateTime, shortSha, showSnackbar} from "~/utils/utils";
import ToolCallLabel from "~/components/chat/ToolCallLabel.vue";
import ToolCallStatusIcon from "~/components/chat/ToolCallStatusIcon.vue";
import IconText from "~/components/IconText.vue";
import {useI18n} from "#i18n";

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  chatId: string,
  repositories: RepositoryDto[],
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const summary = ref<ToolCallSummaryDto | null>(null);
const toolCall = ref<ToolCallDto | null>(null);
const fetching = ref(false);

const repositoryName = computed(() => {
  if (!summary.value) {
    return null;
  }
  const repository = props.repositories.find(r => r.id === summary.value!.repository_id);
  const named = summary.value.input?.repository;
  return repository?.name ?? (typeof named === 'string' ? named : null);
});

const inputJson = computed(() => JSON.stringify(summary.value?.input ?? {}, null, 2));

const fetchToolCall = async () => {
  if (!summary.value) {
    return;
  }
  const id = summary.value.id;
  fetching.value = true;
  try {
    const result = await getToolCall(props.chatId, id);
    if (summary.value?.id === id) {
      toolCall.value = result;
    }
  } catch (e) {
    showSnackbar(t('chat.toolCallDialog.loadFailed', {error: errorMessage(e)}));
  } finally {
    fetching.value = false;
  }
};

defineExpose({
  load: (value: ToolCallSummaryDto) => {
    summary.value = value;
    toolCall.value = null;
    fetchToolCall();
  },
});
</script>

<style scoped>
.tool-call-block {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.8rem;
  line-height: 1.5;
  background: rgba(var(--v-theme-on-surface), 0.05);
  border-radius: 6px;
  padding: 10px 12px;
  overflow: auto;
  white-space: pre;
}

.tool-call-output {
  max-height: 50vh;
}
</style>
