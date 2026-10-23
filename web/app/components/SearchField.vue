<template>
  <v-text-field ref="search-field" v-model="name"
                type="text" append-inner-icon="mdi-magnify" :placeholder="$t('common.search')" variant="solo" hide-details/>
</template>

<script lang="ts" setup>
import {computed, useTemplateRef} from "vue";

const searchField = useTemplateRef('search-field');

const props = defineProps<{
  modelValue: string
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void
}>();

defineExpose({
  focus: () => searchField.value!.focus(),
});

const name = computed({
  get: () => props.modelValue,
  set: (val: string) => emit('update:modelValue', val)
});
</script>
