<template>
  <GenericSaveDialog v-model="dialog" :loading="props.loading" :title="$t('chat.renameDialog.title')" @submit="submit">
    <v-form ref="form" @submit.prevent="submit">
      <v-text-field v-model="title" :label="$t('chat.renameDialog.label')" prepend-inner-icon="mdi-format-title"
                    :disabled="props.loading" :rules="[rules.required, rules.length]" counter="200"/>
    </v-form>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref, useTemplateRef} from "vue";
import {useI18n} from "#i18n";
import type {ChatDto} from "~/utils/model";
import {charCount} from "~/utils/utils";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const MAX_TITLE_LENGTH = 200;

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', title: string): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const form = useTemplateRef<{ validate: () => Promise<{ valid: boolean }> }>('form');

const title = ref('');

const rules = {
  required: (value: string) => !!value.trim() || t('common.required'),
  length: (value: string) => charCount(value.trim()) <= MAX_TITLE_LENGTH
      || t('chat.renameDialog.maxLength', {max: MAX_TITLE_LENGTH}),
};

defineExpose({
  load: (chat: ChatDto) => {
    title.value = chat.title;
  },
});

const submit = async () => {
  const {valid} = await form.value!.validate();
  if (!valid) {
    return;
  }
  emit('submit', title.value.trim());
};
</script>
