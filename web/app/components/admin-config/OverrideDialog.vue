<template>
  <GenericSaveDialog :title="$t('admin.config.overrideAction')" v-model="dialog" :loading="props.loading" @submit="submit">
    <p class="mb-1"><b>{{ props.configKey }}</b></p>
    <i18n-t scope="global" keypath="admin.config.overrideDialog.env" tag="p" class="mb-6 text-medium-emphasis">
      <template v-slot:value>
        <code>{{ props.env }}</code>
      </template>
    </i18n-t>

    <v-select v-if="options" v-model="value" :items="options" :label="$t('admin.config.overrideDialog.value')" :disabled="props.loading" clearable
              :hint="$t('admin.config.overrideDialog.clearHint')" persistent-hint />
    <v-text-field v-else v-model="value" :label="$t('admin.config.overrideDialog.value')" :disabled="props.loading" autofocus clearable
                  :hint="$t('admin.config.overrideDialog.emptyHint')" persistent-hint @keydown.enter="submit" />
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

/** Keys that accept only a few values, see `RuntimeConfig::set` in the API. */
const OPTIONS: Record<string, string[]> = {
  OCR_ENGINE: ['none', 'tesseract', 'paddle', 'mistral'],
};

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  configKey: string,
  env: string,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  /** `null` removes the override. */
  (e: 'submit', value: string | null): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const options = computed(() => OPTIONS[props.configKey]);

const value = ref<string | null>(null);

const submit = () => {
  emit('submit', value.value?.trim() || null);
}

defineExpose({
  reset: (override: string | null) => {
    value.value = override;
  },
});
</script>
