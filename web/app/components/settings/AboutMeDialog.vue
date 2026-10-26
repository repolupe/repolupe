<template>
  <GenericSaveDialog :title="$t('settings.profile.aboutDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-textarea v-model="about" :label="$t('settings.profile.about')" :disabled="loading" prepend-icon="mdi-information"
                :counter="MAX_ABOUT_LENGTH" :rows="4" auto-grow
                :placeholder="$t('settings.profile.aboutDialog.placeholder')" />
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {charCount, showSnackbar, trimmedOrNull} from "~/utils/utils";
import type {UpdateProfilePayload} from "~/utils/api";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

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

const about = ref('');
// Sent unchanged, since the API replaces the whole profile.
const fullName = ref<string | null>(null);
const firstName = ref<string | null>(null);

const submit = () => {
  const aboutValue = trimmedOrNull(about.value);
  if (aboutValue && charCount(aboutValue) > MAX_ABOUT_LENGTH) {
    showSnackbar(t('settings.profile.aboutDialog.tooLong', {max: MAX_ABOUT_LENGTH}));
    return;
  }

  emit('submit', {
    full_name: fullName.value,
    first_name: firstName.value,
    about: aboutValue,
  });
}

defineExpose({
  load: (currentFullName: string | null, currentFirstName: string | null, currentAbout: string | null) => {
    fullName.value = currentFullName;
    firstName.value = currentFirstName;
    about.value = currentAbout ?? '';
  },
});
</script>
