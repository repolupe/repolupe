<template>
  <GenericSaveDialog :title="$t('admin.users.passwordDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <p class="mb-6">{{ $t('admin.users.passwordDialog.intro', {name: props.userName}) }}</p>

    <v-text-field v-model="password" @keydown.enter="submit" :label="$t('user.newPassword')"
                  prepend-icon="mdi-key" :type="showPassword ? 'text' : 'password'" autocomplete="new-password"
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
import {useI18n} from "#i18n";
import {showSnackbar} from "~/utils/utils";
import type {ResetPasswordPayload} from "~/utils/api";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const {t} = useI18n();

const MIN_PASSWORD_LENGTH = 8;
const MAX_PASSWORD_LENGTH = 128;

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  userName: string,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', payload: ResetPasswordPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const password = ref('');
const showPassword = ref(false);
const mustChangePassword = ref(true);

const submit = () => {
  if (!password.value) {
    showSnackbar(t('user.missingPassword'));
    return;
  }

  if (password.value.length < MIN_PASSWORD_LENGTH || password.value.length > MAX_PASSWORD_LENGTH) {
    showSnackbar(t('user.passwordLengthInvalid', {min: MIN_PASSWORD_LENGTH, max: MAX_PASSWORD_LENGTH}));
    return;
  }

  emit('submit', {
    password: password.value,
    must_change_password: mustChangePassword.value,
  });
}

defineExpose({
  reset: () => {
    password.value = '';
    showPassword.value = false;
    mustChangePassword.value = true;
  },
});
</script>
