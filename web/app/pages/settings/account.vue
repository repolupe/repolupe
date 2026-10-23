<template>
  <MainContainer :title="$t('settings.account.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <v-card v-if="user">
      <v-table>
        <tbody>
        <tr>
          <td>{{ $t('user.userName') }}</td>
          <td>{{ user.user_name }}</td>
          <td><v-btn v-if="user.can_change_identity" @click="showIdentityDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        <tr v-if="user.email || user.can_change_identity">
          <td>{{ $t('user.email') }}</td>
          <td>{{ user.email ?? '-' }}</td>
          <td><v-btn v-if="user.can_change_identity" @click="showIdentityDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        <tr>
          <td>{{ $t('user.role') }}</td>
          <td>{{ user.role === UserRole.ADMIN ? $t('user.roleAdmin') : $t('user.roleUser') }}</td>
          <td></td>
        </tr>
        <tr>
          <td>{{ $t('settings.account.page.memberSince') }}</td>
          <td>{{ formatDateTime(user.created_at) }}</td>
          <td></td>
        </tr>
        <tr>
          <td>{{ $t('user.password') }}</td>
          <td>●●●●●●</td>
          <td><v-btn @click="showPasswordDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        </tbody>
      </v-table>
    </v-card>

    <IdentityDialog ref="identity-dialog" v-model="dialogIdentity" :loading="loading" @submit="updateIdentity"/>
    <ChangePasswordDialog ref="password-dialog" v-model="dialogPassword" :loading="loading" @submit="updatePassword"/>
  </MainContainer>
</template>

<script setup lang="ts">
import {ref, useTemplateRef} from "vue";
import {useI18n} from "#i18n";
import {refreshUser, useUser} from "~/composables/states";
import {
  ApiError,
  changePassword,
  type ChangePasswordPayload,
  errorMessage,
  updateMyIdentity,
  type UpdateIdentityPayload,
} from "~/utils/api";
import {ErrorCode, UserRole} from "~/utils/model";
import {formatDateTime, showSnackbar} from "~/utils/utils";
import MainContainer from "~/components/MainContainer.vue";
import ChangePasswordDialog from "~/components/settings/ChangePasswordDialog.vue";
import IdentityDialog from "~/components/settings/IdentityDialog.vue";

const identityDialog = useTemplateRef<InstanceType<typeof IdentityDialog>>('identity-dialog');
const passwordDialog = useTemplateRef<InstanceType<typeof ChangePasswordDialog>>('password-dialog');

const {t} = useI18n();

const user = useUser();

const loading = ref(false);
const dialogIdentity = ref(false);
const dialogPassword = ref(false);

const showIdentityDialog = () => {
  identityDialog.value!.load(user.value!.user_name, user.value!.email);
  dialogIdentity.value = true;
}

const updateIdentity = async (data: UpdateIdentityPayload) => {
  loading.value = true;
  try {
    user.value = await updateMyIdentity(data);
    dialogIdentity.value = false;
    showSnackbar(t('settings.account.page.identitySaved'));
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.USER_NAME_TAKEN) {
      showSnackbar(t('user.userNameTaken'));
    } else if (e instanceof ApiError && e.code === ErrorCode.EMAIL_TAKEN) {
      showSnackbar(t('user.emailTaken'));
    } else {
      showSnackbar(t('settings.account.page.identitySaveFailed', {error: errorMessage(e)}));
    }
  } finally {
    loading.value = false;
  }
}

const showPasswordDialog = () => {
  passwordDialog.value!.reset();
  dialogPassword.value = true;
}

const updatePassword = async (data: ChangePasswordPayload) => {
  loading.value = true;
  try {
    await changePassword(data);
    dialogPassword.value = false;
    await refreshUser();
    showSnackbar(t('settings.account.page.passwordChanged'));
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.WRONG_PASSWORD) {
      showSnackbar(t('user.wrongPassword'));
    } else if (e instanceof ApiError && e.code === ErrorCode.SAME_PASSWORD) {
      showSnackbar(t('user.samePassword'));
    } else {
      showSnackbar(t('settings.account.page.changePasswordFailed', {error: errorMessage(e)}));
    }
  } finally {
    loading.value = false;
  }
}
</script>
