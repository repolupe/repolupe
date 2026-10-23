<template>
  <v-progress-circular v-if="props.status === ToolCallStatus.RUNNING" indeterminate size="14" width="2"/>
  <v-icon v-else-if="props.status === ToolCallStatus.FAILED" icon="mdi-alert-circle-outline" size="16" color="error"/>
</template>

<script setup lang="ts">
import {ToolCallStatus} from "~/utils/model";

const props = defineProps<{
  status: ToolCallStatus,
}>();
</script>
