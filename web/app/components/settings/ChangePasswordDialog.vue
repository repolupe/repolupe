<template>
  <GenericSaveDialog :title="$t('settings.account.changePasswordDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-model="currentPassword" @keydown.enter="submit" :label="$t('user.currentPassword')" :disabled="loading"
                  type="password" autocomplete="current-password" prepend-icon="mdi-lock" class="mb-2" />
    <v-text-field v-model="newPassword" @keydown.enter="submit" :label="$t('user.newPassword')" :disabled="loading"
                  type="password" autocomplete="new-password" prepend-icon="mdi-lock-plus" class="mb-2"
                  :hint="$t('user.passwordHint', {min: MIN_LENGTH, max: MAX_LENGTH})" persistent-hint />
    <v-text-field v-model="confirmPassword" @keydown.enter="submit" :label="$t('user.confirmPassword')" :disabled="loading"
                  type="password" autocomplete="new-password" prepend-icon="mdi-lock-check" class="mb-2" />
    <div class="text-caption text-medium-emphasis">
      {{ $t('settings.account.changePasswordDialog.signOutNote') }}
    </div>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {showSnackbar} from "~/utils/utils";
import type {ChangePasswordPayload} from "~/utils/api";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const MIN_LENGTH = 8;
const MAX_LENGTH = 128;

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', value: ChangePasswordPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const currentPassword = ref('');
const newPassword = ref('');
const confirmPassword = ref('');

const submit = () => {
  if (!currentPassword.value || !newPassword.value || !confirmPassword.value) {
    showSnackbar(t('settings.account.changePasswordDialog.fillAll'));
    return;
  }

  if (newPassword.value.length < MIN_LENGTH || newPassword.value.length > MAX_LENGTH) {
    showSnackbar(t('user.newPasswordLengthInvalid', {min: MIN_LENGTH, max: MAX_LENGTH}));
    return;
  }

  if (newPassword.value !== confirmPassword.value) {
    showSnackbar(t('user.passwordMismatch'));
    return;
  }

  emit('submit', {
    current_password: currentPassword.value,
    new_password: newPassword.value,
  });
}

defineExpose({
  reset: () => {
    currentPassword.value = '';
    newPassword.value = '';
    confirmPassword.value = '';
  },
});
</script>
