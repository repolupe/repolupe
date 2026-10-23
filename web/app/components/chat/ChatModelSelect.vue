<template>
  <ModelSelect v-model="selected" :models="props.models" :fallback-title="$t('common.default')" :fallback-selection="fallbackSelection"
               label="" density="compact" variant="plain" menu-icon="" :disabled="props.disabled" class="plain-select"
               style="max-width: 360px"/>
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
/* the plain variant leaves room for a label above the value; there is no label here, so center icon and value */
.plain-select :deep(.v-field__prepend-inner),
.plain-select :deep(.v-field__input) {
  align-items: center;
  padding-top: 0;
  padding-bottom: 0;
}
</style>
