<template>
  <!-- On the baseline: centered, icons look too low next to small text, as they reach below it -->
  <span class="d-inline-flex align-baseline">
    <v-icon :icon="props.icon" :size="props.size" class="mr-1"/>
    <slot/>
  </span>
</template>

<script setup lang="ts">
const props = withDefaults(defineProps<{
  icon: string,
  size?: number,
}>(), {
  size: 14,
});
</script>
