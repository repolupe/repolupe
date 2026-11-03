<template>
  <GenericSaveDialog v-model="dialog" :loading="props.loading" :title="props.title" :submit-text="props.submitText"
                     submit-icon="mdi-share-variant" @submit="submit">
    <p class="mb-4">{{ props.description }}</p>
    <v-text-field v-model="name" @keydown.enter="submit" :label="$t('user.userNameOrEmail')"
                  prepend-icon="mdi-account" :disabled="props.loading" autofocus/>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {showSnackbar} from "~/utils/utils";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

/** Asks for the user name or email of the user to share something with, e.g. a repository. */
const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  title: string,
  /** What the user gets. */
  description: string,
  submitText: string,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', userNameOrEmail: string): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const {t} = useI18n();

const name = ref('');

const submit = () => {
  // Enter in the field also submits while the share is under way.
  if (props.loading) {
    return;
  }
  const trimmed = name.value.trim();
  if (!trimmed) {
    showSnackbar(t('user.missingUserNameOrEmail'));
    return;
  }
  emit('submit', trimmed);
}

defineExpose({
  reset: () => {
    name.value = '';
  },
});
</script>
