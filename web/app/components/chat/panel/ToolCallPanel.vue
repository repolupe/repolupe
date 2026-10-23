<template>
  <v-card class="d-flex flex-column" variant="flat">
    <div class="d-flex align-center pl-4 pr-2 pt-2">
      <v-icon :icon="props.icon" size="20" class="mr-2"/>
      <span class="text-subtitle-1 text-truncate" :title="heading">{{ heading }}</span>
      <slot name="title-append"/>
      <v-spacer/>
      <slot name="actions"/>
      <v-btn icon="mdi-close" variant="text" size="small" :title="$t('common.close')" :aria-label="$t('common.close')"
             @click="emit('close')"/>
    </div>

    <div class="px-4 pb-2 text-body-2 text-medium-emphasis">
      <IconText v-if="repositoryName" icon="mdi-source-repository" class="file-path" :title="path">
        {{ repositoryName }}<template v-if="path"> › {{ path }}</template>
      </IconText>
      <span v-else class="file-path">{{ path }}</span>
    </div>

    <v-progress-linear :active="props.fetching" indeterminate color="primary"/>
    <v-divider/>

    <div class="panel-body" :class="{'panel-body-fill': props.fill}">
      <!-- fades in when loaded, and goes at once when another one is loading -->
      <Transition name="panel-fade">
        <v-alert v-if="props.error" type="error" variant="tonal" density="compact" :text="props.error" class="ma-4"/>
        <slot v-else/>
      </Transition>
    </div>

    <slot name="footer"/>
  </v-card>
</template>

<script setup lang="ts">
import {computed} from "vue";
import type {RepositoryDto, ToolCallSummaryDto} from "~/utils/model";
import {fileName, toolCallPath} from "~/utils/utils";
import IconText from "~/components/IconText.vue";

/** The frame of a panel that shows what a tool call refers to (a file, or the moves of `move_files`); the slot shows it once it is loaded. */
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

.panel-body {
  flex: 1;
  min-height: 0;
  overflow: auto;
}

.panel-body-fill {
  overflow: hidden;
}

.panel-fade-enter-active {
  transition: opacity 200ms ease-out;
}

.panel-fade-enter-from {
  opacity: 0;
}

@media (prefers-reduced-motion: reduce) {
  .panel-fade-enter-active {
    transition: none;
  }
}
</style>
