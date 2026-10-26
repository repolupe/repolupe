<template>
  <GenericSaveDialog :title="$t('settings.profile.fullNameDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-model="fullName" @keydown.enter="submit" :label="$t('settings.profile.fullName')" :disabled="loading"
                  prepend-icon="mdi-account" class="mb-2" :counter="MAX_FULL_NAME_LENGTH"
                  :hint="$t('settings.profile.fullNameDialog.hint')" persistent-hint />
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {charCount, showSnackbar, trimmedOrNull} from "~/utils/utils";
import type {UpdateProfilePayload} from "~/utils/api";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const MAX_FULL_NAME_LENGTH = 100;

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', value: UpdateProfilePayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const fullName = ref('');
// Sent unchanged, since the API replaces the whole profile.
const firstName = ref<string | null>(null);
const about = ref<string | null>(null);

const submit = () => {
  const fullNameValue = trimmedOrNull(fullName.value);
  if (fullNameValue && charCount(fullNameValue) > MAX_FULL_NAME_LENGTH) {
    showSnackbar(t('settings.profile.fullNameDialog.tooLong', {max: MAX_FULL_NAME_LENGTH}));
    return;
  }

  emit('submit', {
    full_name: fullNameValue,
    first_name: firstName.value,
    about: about.value,
  });
}

defineExpose({
  load: (currentFullName: string | null, currentFirstName: string | null, currentAbout: string | null) => {
    fullName.value = currentFullName ?? '';
    firstName.value = currentFirstName;
    about.value = currentAbout;
  },
});
</script>
