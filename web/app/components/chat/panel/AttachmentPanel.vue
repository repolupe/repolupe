<template>
  <PanelFrame icon="mdi-paperclip" :heading="props.attachment.file_name" :fetching="fetching" :error="error"
              :fill="file?.kind === 'pdf'" @close="emit('close')">
    <template v-slot:subtitle>{{ formatBytes(props.attachment.size) }}</template>
    <template v-slot:actions>
      <v-btn icon="mdi-download" variant="text" size="small" :title="$t('common.download')"
             :aria-label="$t('common.download')" :href="attachmentUrl(props.attachment.id)"
             :download="props.attachment.file_name"/>
    </template>

    <FilePreview v-if="file" :file="file" :name="props.attachment.file_name"/>
  </PanelFrame>
</template>

<script setup lang="ts">
import {onBeforeUnmount, ref, watch} from "vue";
import type {AttachmentDto} from "~/utils/model";
import {attachmentUrl, errorMessage, getAttachmentFile} from "~/utils/api";
import {attachmentPreviewKind, formatBytes, type LoadedFile} from "~/utils/utils";
import FilePreview from "~/components/chat/panel/FilePreview.vue";
import PanelFrame from "~/components/chat/panel/PanelFrame.vue";

const props = defineProps<{
  /** One that `attachmentPreviewKind` can show. */
  attachment: AttachmentDto,
}>();

const emit = defineEmits<{
  (e: 'close'): void,
}>();

const file = ref<LoadedFile | null>(null);
const error = ref<string | null>(null);
const fetching = ref(false);

const setFile = (value: LoadedFile | null) => {
  if (file.value) {
    URL.revokeObjectURL(file.value.url);
  }
  file.value = value;
};

const fetchFile = async () => {
  const id = props.attachment.id;
  const kind = attachmentPreviewKind(props.attachment);
  setFile(null);
  error.value = null;
  fetching.value = !!kind;
  if (!kind) {
    return;
  }
  try {
    const {blob} = await getAttachmentFile(id);
    // the frame of the PDF viewer would run any other type the user uploaded, like HTML, as a page of this site
    const url = URL.createObjectURL(kind === 'pdf' ? blob.slice(0, blob.size, 'application/pdf') : blob);
    const loaded: LoadedFile = kind === 'pdf' || kind === 'image' ? {kind, url} : {kind, url, text: await blob.text()};
    if (props.attachment.id === id) {
      setFile(loaded);
    } else {
      URL.revokeObjectURL(loaded.url);
    }
  } catch (e) {
    if (props.attachment.id === id) {
      error.value = errorMessage(e);
    }
  } finally {
    if (props.attachment.id === id) {
      fetching.value = false;
    }
  }
};

watch(() => props.attachment.id, fetchFile, {immediate: true});

// PDFs and images can be large
onBeforeUnmount(() => setFile(null));
</script>
