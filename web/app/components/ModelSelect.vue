<template>
  <v-select v-model="selected" :items="items" :label="props.label ?? $t('common.model')" :prepend-inner-icon="props.icon"
            :disabled="props.disabled" :density="props.density" hide-details>
    <template v-slot:selection="{ item }">
      {{ item.value === FALLBACK && props.fallbackSelection ? props.fallbackSelection : item.title }}
    </template>
  </v-select>
</template>

<script setup lang="ts">
import {computed} from "vue";
import type {ModelDto} from "~/utils/model";

/** Stands for `null` (the fallback model), since a select handles a string value more reliably. */
const FALLBACK = '__fallback__';

const props = withDefaults(defineProps<{
  /** `null` selects the fallback entry. */
  modelValue: string | null,
  models: ModelDto[],
  /** Title of the entry for `null`, e.g. `Default (Opus)`. */
  fallbackTitle: string,
  /** Shown in the field instead of `fallbackTitle` while the fallback is selected, e.g. the model it resolves to. */
  fallbackSelection?: string,
  /** Defaults to `common.model`. */
  label?: string,
  icon?: string,
  disabled?: boolean,
  density?: 'default' | 'comfortable' | 'compact',
}>(), {
  icon: 'mdi-robot-outline',
  disabled: false,
  density: 'default',
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string | null): void,
}>();

const selected = computed({
  // a model that no longer exists counts as the fallback, like on the server
  get: () => props.modelValue && props.models.some(m => m.id === props.modelValue) ? props.modelValue : FALLBACK,
  set: (val: string) => emit('update:modelValue', val === FALLBACK ? null : val),
});

const items = computed(() => {
  const result: { title: string, value?: string, type?: 'subheader' }[] = [
    {title: props.fallbackTitle, value: FALLBACK},
  ];

  // grouped by provider, in the order the API returns them
  const providers = new Map<string, { name: string, models: ModelDto[] }>();
  for (const m of props.models) {
    const group = providers.get(m.provider_id);
    if (group) {
      group.models.push(m);
    } else {
      providers.set(m.provider_id, {name: m.provider_name, models: [m]});
    }
  }
  // the provider headings only help to tell several providers apart
  const showProviders = providers.size > 1;
  for (const {name, models} of providers.values()) {
    if (showProviders) {
      result.push({title: name, type: 'subheader'});
    }
    for (const m of models) {
      result.push({title: m.display_name, value: m.id});
    }
  }
  return result;
});
</script>
