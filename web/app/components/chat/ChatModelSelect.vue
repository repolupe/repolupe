<template>
  <!-- quiet text next to the send button, as wide as the model's name -->
  <ModelSelect v-model="selected" :models="props.models" :fallback-title="$t('common.default')" :fallback-selection="fallbackSelection"
               label="" icon="" menu-icon="" density="compact" variant="plain" :disabled="props.disabled" class="plain-select"/>
</template>

<script setup lang="ts">
import {computed} from "vue";
import type {ModelDto} from "~/utils/model";
import {resolveModel} from "~/utils/utils";
import {useUser} from "~/composables/states";
import ModelSelect from "~/components/ModelSelect.vue";

const props = defineProps<{
  /** `null` uses the user's model. */
  modelValue: string | null,
  models: ModelDto[],
  disabled?: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: string | null): void,
}>();

const user = useUser();

const selected = computed({
  get: () => props.modelValue,
  set: (val: string | null) => emit('update:modelValue', val),
});

/** The model the "Default" entry resolves to. */
const fallbackSelection = computed(() => resolveModel(props.models, user.value?.default_model_id)?.display_name);
</script>

<style scoped>
.plain-select {
  flex: 0 1 auto;
  min-width: 0;
  max-width: 280px;
  font-size: 0.875rem;
  color: rgba(var(--v-theme-on-surface), var(--v-medium-emphasis-opacity));
}

/* the plain variant leaves room for a label above the value; there is no label here, so center the value */
.plain-select :deep(.v-field__input) {
  align-items: center;
  flex-wrap: nowrap;
  padding-top: 0;
  padding-bottom: 0;
}

/* a long name is cut off, the select's selection slot renders it as plain text */
.plain-select :deep(.v-select__selection) {
  display: block;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
