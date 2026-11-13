<template>
  <v-card class="d-flex flex-column" variant="flat">
    <div class="d-flex align-center pl-4 pr-2 pt-2">
      <v-icon :icon="props.icon" size="20" class="mr-2"/>
      <span class="text-subtitle-1 text-truncate" :title="props.heading">{{ props.heading }}</span>
      <slot name="title-append"/>
      <v-spacer/>
      <slot name="actions"/>
      <v-btn icon="mdi-close" variant="text" size="small" :title="$t('common.close')" :aria-label="$t('common.close')"
             @click="emit('close')"/>
    </div>

    <div class="px-4 pb-2 text-body-2 text-medium-emphasis">
      <slot name="subtitle"/>
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
/** The frame of a panel next to the chat; the slot shows its content once it is loaded. */
const props = defineProps<{
  icon: string,
  heading: string,
  fetching: boolean,
  error: string | null,
  /** Whether the content fills the body instead of scrolling in it, like the PDF viewer. */
  fill?: boolean,
}>();

const emit = defineEmits<{
  (e: 'close'): void,
}>();
</script>

<style scoped>
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
