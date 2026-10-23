<template>
  <GenericSaveDialog :title="$t('admin.users.createDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-model="userName" @keydown.enter="submit" :label="$t('user.userName')"
                  prepend-icon="mdi-account" :disabled="props.loading" />

    <v-text-field v-model="email" @keydown.enter="submit" :label="$t('user.emailOptional')" type="email"
                  prepend-icon="mdi-email" :disabled="props.loading" />

    <v-text-field v-model="password" @keydown.enter="submit" :label="$t('user.password')"
                  prepend-icon="mdi-key" :type="showPassword ? 'text' : 'password'"
                  :append-inner-icon="showPassword ? 'mdi-eye-off' : 'mdi-eye'"
                  @click:append-inner="showPassword = !showPassword"
                  :hint="$t('user.passwordHint', {min: MIN_PASSWORD_LENGTH, max: MAX_PASSWORD_LENGTH})" persistent-hint
                  :disabled="props.loading" class="mb-2" />

    <v-switch v-model="mustChangePassword" :label="$t('admin.users.mustChangePassword')" color="primary"
              :hint="$t('admin.users.chooseOwnPasswordHint')" persistent-hint :disabled="props.loading" />
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {showSnackbar, userNameOrEmailError} from "~/utils/utils";
import type {RegisterUserPayload} from "~/utils/api";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";
import {useI18n} from "#i18n";

const {t} = useI18n();

const MIN_PASSWORD_LENGTH = 8;
const MAX_PASSWORD_LENGTH = 128;

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', payload: RegisterUserPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const userName = ref('');
const email = ref('');
const password = ref('');
const showPassword = ref(false);
const mustChangePassword = ref(true);

const submit = () => {
  const trimmedUserName = userName.value.trim();
  const trimmedEmail = email.value.trim();
  const error = userNameOrEmailError(trimmedUserName, trimmedEmail);
  if (error) {
    showSnackbar(error);
    return;
  }

  if (!password.value) {
    showSnackbar(t('user.missingPassword'));
    return;
  }

  if (password.value.length < MIN_PASSWORD_LENGTH || password.value.length > MAX_PASSWORD_LENGTH) {
    showSnackbar(t('user.passwordLengthInvalid', {min: MIN_PASSWORD_LENGTH, max: MAX_PASSWORD_LENGTH}));
    return;
  }

  emit('submit', {
    user_name: trimmedUserName,
    email: trimmedEmail || null,
    password: password.value,
    must_change_password: mustChangePassword.value,
  });
}

defineExpose({
  reset: () => {
    userName.value = '';
    email.value = '';
    password.value = '';
    showPassword.value = false;
    mustChangePassword.value = true;
  },
});
</script>
