<template>
  <PanelFrame :icon="props.icon" :heading="heading" :fetching="props.fetching" :error="props.error" :fill="props.fill"
              @close="emit('close')">
    <template v-slot:title-append>
      <slot name="title-append"/>
    </template>
    <template v-slot:subtitle>
      <IconText v-if="repositoryName" icon="mdi-source-repository" class="file-path" :title="path">
        {{ repositoryName }}<template v-if="path"> › {{ path }}</template>
      </IconText>
      <span v-else class="file-path">{{ path }}</span>
    </template>
    <template v-slot:actions>
      <slot name="actions"/>
    </template>

    <slot/>

    <template v-slot:footer>
      <slot name="footer"/>
    </template>
  </PanelFrame>
</template>

<script setup lang="ts">
import {computed} from "vue";
import type {RepositoryDto, ToolCallSummaryDto} from "~/utils/model";
import {fileName, toolCallPath} from "~/utils/utils";
import IconText from "~/components/IconText.vue";
import PanelFrame from "~/components/chat/panel/PanelFrame.vue";

/** A panel that shows what a tool call refers to (a file, or the moves of `move_files`); the slot shows it once it is loaded. */
const props = defineProps<{
  icon: string,
  toolCall: ToolCallSummaryDto,
  repositories: RepositoryDto[],
  fetching: boolean,
  error: string | null,
  /** Whether the content fills the body instead of scrolling in it, like the PDF viewer. */
  fill?: boolean,
  /** The heading, the file name if empty, so calls without a path need one. */
  title?: string,
}>();

const emit = defineEmits<{
  (e: 'close'): void,
}>();

const path = computed(() => toolCallPath(props.toolCall) ?? '');

const heading = computed(() => props.title || fileName(path.value));

const repositoryName = computed(() => {
  const repository = props.repositories.find(r => r.id === props.toolCall.repository_id);
  const named = props.toolCall.input?.repository;
  return repository?.name ?? (typeof named === 'string' ? named : null);
});
</script>

<style scoped>
.file-path {
  overflow-wrap: anywhere;
}
</style>
