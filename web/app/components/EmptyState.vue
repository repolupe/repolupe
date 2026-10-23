<template>
  <v-card>
    <v-card-text class="text-center py-12">
      <v-icon size="48" class="mb-4" color="medium-emphasis">{{ props.icon }}</v-icon>
      <p class="text-h6 mb-2">{{ props.title }}</p>
      <p class="text-medium-emphasis mx-auto" style="max-width: 520px">
        <slot/>
      </p>
      <v-btn @click="emit('action')" class="mt-6" color="primary" prepend-icon="mdi-plus" :text="props.actionText"/>
    </v-card-text>
  </v-card>
</template>

<script setup lang="ts">
const props = defineProps<{
  icon: string,
  title: string,
  actionText: string,
}>();

const emit = defineEmits<{
  action: [],
}>();
</script>
