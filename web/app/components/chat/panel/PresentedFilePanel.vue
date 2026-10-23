<template>
  <ToolCallPanel icon="mdi-file-document-outline" :tool-call="props.toolCall" :repositories="props.repositories"
                 :fetching="fetching" :error="error" :fill="file?.kind === 'pdf'" @close="emit('close')">
    <template v-slot:actions>
      <v-btn v-if="file" icon="mdi-download" variant="text" size="small" :title="$t('common.download')"
             :aria-label="$t('common.download')" :href="file.url" :download="fileName(path)"/>
    </template>

    <iframe v-if="file?.kind === 'pdf'" :src="file.url" :title="path" class="file-pdf"/>
    <MarkdownContent v-else-if="file?.kind === 'markdown'" :content="file.text" class="text-body-1 pa-4"/>
    <pre v-else-if="file" class="file-text ma-4">{{ file.text }}</pre>
  </ToolCallPanel>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, ref, watch} from "vue";
import type {RepositoryDto, ToolCallSummaryDto} from "~/utils/model";
import {errorMessage, getPresentedFile} from "~/utils/api";
import {fileName, toolCallPath} from "~/utils/utils";
import MarkdownContent from "~/components/chat/MarkdownContent.vue";
import ToolCallPanel from "~/components/chat/panel/ToolCallPanel.vue";

const props = defineProps<{
  chatId: string,
  /** The `present_file_to_user` call that showed the file. */
  toolCall: ToolCallSummaryDto,
  repositories: RepositoryDto[],
}>();

const emit = defineEmits<{
  (e: 'close'): void,
}>();

/** The file as it is shown. `url` is an object URL of its content, for the PDF viewer and the download. */
type LoadedFile =
    | { kind: 'pdf', url: string }
    | { kind: 'markdown' | 'text', url: string, text: string };

const file = ref<LoadedFile | null>(null);
const error = ref<string | null>(null);
const fetching = ref(false);

const path = computed(() => toolCallPath(props.toolCall) ?? '');

const setFile = (value: LoadedFile | null) => {
  if (file.value) {
    URL.revokeObjectURL(file.value.url);
  }
  file.value = value;
};

const fetchFile = async () => {
  const id = props.toolCall.id;
  setFile(null);
  error.value = null;
  fetching.value = true;
  try {
    const {contentType, blob} = await getPresentedFile(props.chatId, id);
    const type = contentType.split(';')[0]!.trim().toLowerCase();
    const loaded: LoadedFile = type === 'application/pdf'
        ? {kind: 'pdf', url: URL.createObjectURL(blob)}
        : {kind: type === 'text/markdown' ? 'markdown' : 'text', url: URL.createObjectURL(blob), text: await blob.text()};
    if (props.toolCall.id === id) {
      setFile(loaded);
    } else {
      URL.revokeObjectURL(loaded.url);
    }
  } catch (e) {
    if (props.toolCall.id === id) {
      error.value = errorMessage(e);
    }
  } finally {
    if (props.toolCall.id === id) {
      fetching.value = false;
    }
  }
};

watch(() => props.toolCall.id, fetchFile, {immediate: true});

// PDFs can be large
onBeforeUnmount(() => setFile(null));
</script>

<style scoped>
.file-text {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.8rem;
  line-height: 1.5;
  background: rgba(0, 0, 0, 0.05);
  border-radius: 6px;
  padding: 10px 12px;
  overflow: auto;
  white-space: pre;
}

.file-pdf {
  display: block;
  width: 100%;
  height: 100%;
  border: 0;
}
</style>
