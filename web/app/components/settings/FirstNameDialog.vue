<template>
  <GenericSaveDialog :title="$t('settings.profile.firstNameDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-model="firstName" @keydown.enter="submit" :label="$t('settings.profile.firstName')" :disabled="loading"
                  prepend-icon="mdi-account-outline" class="mb-2" :counter="MAX_FIRST_NAME_LENGTH" />
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {charCount, showSnackbar, trimmedOrNull} from "~/utils/utils";
import type {UpdateProfilePayload} from "~/utils/api";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const MAX_FIRST_NAME_LENGTH = 100;

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

const firstName = ref('');
// Sent unchanged, since the API replaces the whole profile.
const fullName = ref<string | null>(null);
const about = ref<string | null>(null);

const submit = () => {
  const firstNameValue = trimmedOrNull(firstName.value);
  if (firstNameValue && charCount(firstNameValue) > MAX_FIRST_NAME_LENGTH) {
    showSnackbar(t('settings.profile.firstNameDialog.tooLong', {max: MAX_FIRST_NAME_LENGTH}));
    return;
  }

  emit('submit', {
    full_name: fullName.value,
    first_name: firstNameValue,
    about: about.value,
  });
}

defineExpose({
  load: (currentFullName: string | null, currentFirstName: string | null, currentAbout: string | null) => {
    fullName.value = currentFullName;
    firstName.value = currentFirstName ?? '';
    about.value = currentAbout;
  },
});
</script>
