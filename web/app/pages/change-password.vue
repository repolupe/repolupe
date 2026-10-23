<template>
  <div style="min-height: 100vh; width: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center">
    <div style="text-align: center">
      <p class="text-h3"><InstanceTitle/></p>
      <v-card class="mt-10" style="width: 400px; max-width: calc(100vw - 32px)" :title="$t('login.changePasswordPage.title')">
        <v-card-text class="pa-6 pt-2">
          <v-text-field ref="new-password" v-model="newPassword" @keydown.enter="submit" :label="$t('user.newPassword')"
                        type="password" autocomplete="new-password" :disabled="loading" variant="filled" class="mb-2"
                        :hint="$t('user.passwordHint', {min: MIN_LENGTH, max: MAX_LENGTH})" persistent-hint />
          <v-text-field v-model="confirmPassword" @keydown.enter="submit" :label="$t('user.confirmPassword')"
                        type="password" autocomplete="new-password" :disabled="loading" variant="filled" hide-details />
          <div class="mt-6" style="display: flex; justify-content: space-between">
            <v-btn @click="doLogout" variant="text" :disabled="loading" :text="$t('login.changePasswordPage.logout')" />
            <v-btn @click="submit" color="primary" :loading="loading" :disabled="!filled" append-icon="mdi-arrow-right"
                   :text="$t('login.changePasswordPage.submit')" />
          </div>
        </v-card-text>
      </v-card>
    </div>
  </div>
</template>

<script lang="ts" setup>
import {computed, onMounted, ref, useTemplateRef} from "vue";
import {navigateTo} from "#app";
import {useI18n} from "#i18n";
import {ApiError, changePassword, errorMessage, logout} from "~/utils/api";
import {ErrorCode} from "~/utils/model";
import {showSnackbar} from "~/utils/utils";
import {refreshUser, takeLoginPassword, useUser} from "~/composables/states";
import InstanceTitle from "~/components/InstanceTitle.vue";

const MIN_LENGTH = 8;
const MAX_LENGTH = 128;

const newPasswordField = useTemplateRef('new-password');

const currentPassword = takeLoginPassword();
const newPassword = ref('');
const confirmPassword = ref('');
const loading = ref(false);
const user = useUser();
const {t} = useI18n();

const filled = computed(() => !!newPassword.value && !!confirmPassword.value);

const submit = async () => {
  if (loading.value || !filled.value || currentPassword === null) {
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

  loading.value = true;
  try {
    await changePassword({current_password: currentPassword, new_password: newPassword.value});
    // ends the required change, which lets the middleware through
    await refreshUser();
    await navigateTo('/');
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.WRONG_PASSWORD) {
      // e.g. changed in another session meanwhile
      await doLogout();
    } else if (e instanceof ApiError && e.code === ErrorCode.SAME_PASSWORD) {
      showSnackbar(t('user.samePassword'));
    } else {
      showSnackbar(t('settings.account.page.changePasswordFailed', {error: errorMessage(e)}));
    }
  } finally {
    loading.value = false;
  }
};

const doLogout = async () => {
  try {
    await logout();
  } finally {
    user.value = null;
  }
};

onMounted(async () => {
  if (currentPassword === null) {
    await doLogout();
    return;
  }
  newPasswordField.value?.focus();
});
</script>
