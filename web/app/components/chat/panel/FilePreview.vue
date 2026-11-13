<template>
  <iframe v-if="props.file.kind === 'pdf'" :src="props.file.url" :title="props.name" class="file-pdf"/>
  <img v-else-if="props.file.kind === 'image'" :src="props.file.url" :alt="props.name" class="file-image pa-4">
  <MarkdownContent v-else-if="props.file.kind === 'markdown'" :content="props.file.text" class="text-body-1 pa-4"/>
  <pre v-else class="file-text ma-4">{{ props.file.text }}</pre>
</template>

<script setup lang="ts">
import type {LoadedFile} from "~/utils/utils";
import MarkdownContent from "~/components/chat/MarkdownContent.vue";

/** A file in a panel next to the chat. A PDF fills the body of the panel. */
const props = defineProps<{
  file: LoadedFile,
  /** What screen readers call the PDF or image. */
  name: string,
}>();
</script>

<style scoped>
.file-text {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.8rem;
  line-height: 1.5;
  background: rgba(var(--v-theme-on-surface), 0.05);
  border-radius: 6px;
  padding: 10px 12px;
  overflow: auto;
  white-space: pre;
}

/* As large as it is, scaled down to the width of the panel. */
.file-image {
  display: block;
  max-width: 100%;
  height: auto;
  margin: 0 auto;
}

.file-pdf {
  display: block;
  width: 100%;
  height: 100%;
  border: 0;
}
</style>
