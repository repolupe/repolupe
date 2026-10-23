<template>
  <GenericSaveDialog :title="$t('settings.profile.dialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <div class="text-body-2 text-grey-darken-1 mb-4">
      {{ $t('settings.profile.dialog.description') }}
    </div>
    <v-text-field v-model="fullName" @keydown.enter="submit" :label="$t('settings.profile.fullName')" :disabled="loading"
                  prepend-icon="mdi-account" class="mb-2" :counter="MAX_FULL_NAME_LENGTH"
                  :hint="$t('settings.profile.dialog.fullNameHint')" persistent-hint />
    <v-text-field v-model="firstName" @keydown.enter="submit" :label="$t('settings.profile.firstName')" :disabled="loading"
                  prepend-icon="mdi-account-outline" class="mb-2" :counter="MAX_FIRST_NAME_LENGTH" />
    <v-textarea v-model="about" :label="$t('settings.profile.about')" :disabled="loading" prepend-icon="mdi-information"
                :counter="MAX_ABOUT_LENGTH" :rows="4" auto-grow
                :placeholder="$t('settings.profile.dialog.aboutPlaceholder')" />
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {charCount, showSnackbar, trimmedOrNull} from "~/utils/utils";
import type {UpdateProfilePayload} from "~/utils/api";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const MAX_FULL_NAME_LENGTH = 100;
const MAX_FIRST_NAME_LENGTH = 100;
const MAX_ABOUT_LENGTH = 1000;

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
const firstName = ref('');
const about = ref('');

const submit = () => {
  const fullNameValue = trimmedOrNull(fullName.value);
  const firstNameValue = trimmedOrNull(firstName.value);
  const aboutValue = trimmedOrNull(about.value);

  if (fullNameValue && charCount(fullNameValue) > MAX_FULL_NAME_LENGTH) {
    showSnackbar(t('settings.profile.dialog.fullNameTooLong', {max: MAX_FULL_NAME_LENGTH}));
    return;
  }

  if (firstNameValue && charCount(firstNameValue) > MAX_FIRST_NAME_LENGTH) {
    showSnackbar(t('settings.profile.dialog.firstNameTooLong', {max: MAX_FIRST_NAME_LENGTH}));
    return;
  }

  if (aboutValue && charCount(aboutValue) > MAX_ABOUT_LENGTH) {
    showSnackbar(t('settings.profile.dialog.aboutTooLong', {max: MAX_ABOUT_LENGTH}));
    return;
  }

  emit('submit', {
    full_name: fullNameValue,
    first_name: firstNameValue,
    about: aboutValue,
  });
}

defineExpose({
  load: (currentFullName: string | null, currentFirstName: string | null, currentAbout: string | null) => {
    fullName.value = currentFullName ?? '';
    firstName.value = currentFirstName ?? '';
    about.value = currentAbout ?? '';
  },
});
</script>
