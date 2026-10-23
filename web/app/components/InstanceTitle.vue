<template>
  <span class="instance-title" :class="{'instance-title-loading': instanceName === null}">{{ title }}</span>
</template>

<script setup lang="ts">
import {useInstanceName, useInstanceTitle} from "~/composables/states";

const instanceName = useInstanceName();
const title = useInstanceTitle();
</script>

<style scoped>
/* On app load, the instance name fades in once loaded, instead of replacing the product name. */
.instance-title {
  transition: opacity 250ms;
}

.instance-title-loading {
  opacity: 0;
}
</style>
