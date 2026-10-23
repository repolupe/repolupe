<template>
  <v-dialog v-model="dialog" width="auto">
    <v-card width="500" :title="props.title">
      <template v-slot:text>
        <slot></slot>
      </template>

      <template v-slot:actions>
        <v-btn :text="$t('common.cancel')" @click="dialog = false"/>

        <v-btn @click="emit('confirm')" color="primary" variant="elevated" :loading="props.loading"
               :prepend-icon="props.confirmIcon" :text="props.confirmText"/>
      </template>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed} from "vue";

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  title: string,
  confirmText: string,
  confirmIcon: string,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'confirm'): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});
</script>
