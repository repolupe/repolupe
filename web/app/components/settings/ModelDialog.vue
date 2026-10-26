<template>
  <GenericSaveDialog :title="$t('settings.preferences.modelDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <div class="text-body-2 text-medium-emphasis mb-4">
      {{ $t('settings.preferences.modelDialog.description') }}
    </div>
    <ModelSelect v-model="selected" :models="props.models" :fallback-title="fallbackTitle" :disabled="loading"/>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import type {ModelDto} from "~/utils/model";
import {useI18n} from "#i18n";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";
import ModelSelect from "~/components/ModelSelect.vue";

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  models: ModelDto[],
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', modelId: string | null): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const {t} = useI18n();

const selected = ref<string | null>(null);

const fallbackTitle = computed(() => {
  const defaultModel = props.models.find(m => m.is_default);
  return defaultModel
    ? t('settings.preferences.defaultModel', {name: defaultModel.display_name})
    : t('settings.preferences.defaultNone');
});

const submit = () => {
  emit('submit', selected.value);
}

defineExpose({
  load: (modelId: string | null) => {
    // a model that no longer exists counts as the default, like on the server
    selected.value = modelId && props.models.some(m => m.id === modelId) ? modelId : null;
  },
});
</script>
