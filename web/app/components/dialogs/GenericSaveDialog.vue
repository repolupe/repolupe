<template>
  <v-dialog v-model="dialog" width="auto">
    <v-card width="500" :title="props.title">
      <template v-slot:text>
        <slot />
      </template>

      <template v-slot:actions>
        <v-btn :text="$t('common.cancel')" @click="dialog = false"/>

        <v-btn @click="emit('submit')" color="primary" variant="elevated" :loading="props.loading"
               :prepend-icon="props.submitIcon ?? 'mdi-content-save'" :text="props.submitText ?? $t('common.save')" />
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
  /** Instead of "Save". */
  submitText?: string,
  submitIcon?: string,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit'): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});
</script>
