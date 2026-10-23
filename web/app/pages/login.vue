<template>
  <div style="min-height: 100vh; width: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center">
    <div style="text-align: center">
      <p class="text-h3"><InstanceTitle/></p>
      <v-card class="mt-10" style="width: 350px; max-width: calc(100vw - 32px)">
        <v-card-text class="pa-6">
          <v-text-field ref="login-name" v-model="name" @keydown.enter="submitLogin" :label="$t('user.userNameOrEmail')" autocomplete="username" :disabled="loading" variant="filled" hide-details />
          <br>
          <v-text-field ref="login-password" v-model="password" @keydown.enter="submitLogin" type="password" :label="$t('user.password')" autocomplete="current-password" :disabled="loading" variant="filled" hide-details />
          <br>
          <div style="text-align: right">
            <v-btn @click="submitLogin" color="primary" :loading="loading" append-icon="mdi-arrow-right">
              {{ $t('login.login') }}
            </v-btn>
          </div>
        </v-card-text>
      </v-card>
    </div>
  </div>
</template>

<script lang="ts" setup>
import {nextTick, onMounted, ref, useTemplateRef} from "vue";
import {navigateTo} from "#app";
import {useI18n} from "#i18n";
import {ApiError, errorMessage, login} from "~/utils/api";
import {showSnackbar} from "~/utils/utils";
import {rememberLoginPassword, useUser} from "~/composables/states";
import InstanceTitle from "~/components/InstanceTitle.vue";

const loginName = useTemplateRef('login-name');
const loginPassword = useTemplateRef('login-password');

const name = ref('');
const password = ref('');
const loading = ref(false);
const user = useUser();
const {t} = useI18n();

const submitLogin = async () => {
  if (loading.value) {
    return;
  }

  const trimmedName = name.value.trim();
  if (trimmedName && !password.value) {
    loginPassword.value?.focus();
    return;
  } else if (!trimmedName && password.value) {
    loginName.value?.focus();
    return;
  } else if (!trimmedName || !password.value) {
    return;
  }

  loading.value = true;
  let wrongCredentials = false;
  try {
    const loggedIn = await login({user_name_or_email: trimmedName, password: password.value});
    if (loggedIn.must_change_password) {
      rememberLoginPassword(password.value);
    }
    user.value = loggedIn;
    await navigateTo('/');
  } catch (e) {
    if (e instanceof ApiError && e.status === 401) {
      wrongCredentials = true;
      showSnackbar(t('login.wrongCredentials'));
    } else {
      showSnackbar(t('login.loginFailed', {error: errorMessage(e)}));
    }
  } finally {
    loading.value = false;
  }

  if (wrongCredentials) {
    // the field is focusable again only once it is no longer disabled
    password.value = '';
    await nextTick();
    loginPassword.value?.focus();
  }
};

onMounted(() => {
  loginName.value?.focus();
});
</script>
