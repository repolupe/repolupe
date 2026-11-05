<template>
  <span>{{ props.format(value) }}</span>
</template>

<script setup lang="ts">
import {useAnimatedNumber} from "~/composables/animatedNumber";

/** A number that counts to each new value, see `useAnimatedNumber`. */
const props = defineProps<{
  value: number,
  /** Gets the numbers in between too, not only `value`. */
  format: (value: number) => string,
}>();

const value = useAnimatedNumber(() => props.value);
</script>
