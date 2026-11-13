<template>
  <ToolCallPanel icon="mdi-file-document-outline" :tool-call="props.toolCall" :repositories="props.repositories"
                 :fetching="fetching" :error="error" :fill="file?.kind === 'pdf'" @close="emit('close')">
    <template v-slot:actions>
      <v-btn v-if="file" icon="mdi-download" variant="text" size="small" :title="$t('common.download')"
             :aria-label="$t('common.download')" :href="file.url" :download="fileName(path)"/>
    </template>

    <FilePreview v-if="file" :file="file" :name="path"/>
  </ToolCallPanel>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, ref, watch} from "vue";
import type {RepositoryDto, ToolCallSummaryDto} from "~/utils/model";
import {errorMessage, getPresentedFile} from "~/utils/api";
import {fileName, toolCallPath, type LoadedFile} from "~/utils/utils";
import FilePreview from "~/components/chat/panel/FilePreview.vue";
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
    const url = URL.createObjectURL(blob);
    const loaded: LoadedFile = type === 'application/pdf' ? {kind: 'pdf', url}
        : type.startsWith('image/') ? {kind: 'image', url}
        : {kind: type === 'text/markdown' ? 'markdown' : 'text', url, text: await blob.text()};
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

// PDFs and images can be large
onBeforeUnmount(() => setFile(null));
</script>
