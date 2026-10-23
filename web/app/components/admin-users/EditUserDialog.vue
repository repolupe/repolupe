<template>
  <GenericSaveDialog :title="$t('admin.users.editDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-model="userName" @keydown.enter="submit" :label="$t('user.userName')"
                  prepend-icon="mdi-account" :disabled="props.loading" />

    <v-text-field v-model="email" @keydown.enter="submit" :label="$t('user.emailOptional')" type="email"
                  prepend-icon="mdi-email" :disabled="props.loading" class="mb-2" />

    <v-switch v-model="canLogin" :label="$t('admin.users.editDialog.canLogin')" color="primary" :disabled="props.loading || isAdmin"
              :hint="isAdmin ? $t('admin.users.editDialog.adminUnrestricted') : $t('admin.users.editDialog.canLoginHint')"
              persistent-hint class="mb-4" />

    <v-switch v-model="canManageRepositories" :label="$t('admin.users.editDialog.canManageRepositories')" color="primary"
              :disabled="props.loading || isAdmin"
              :hint="isAdmin ? $t('admin.users.editDialog.adminUnrestricted') : $t('admin.users.editDialog.canManageRepositoriesHint')"
              persistent-hint class="mb-4" />

    <v-switch v-model="canChangeIdentity" :label="$t('admin.users.editDialog.canChangeIdentity')" color="primary"
              :disabled="props.loading || isAdmin"
              :hint="isAdmin ? $t('admin.users.editDialog.adminUnrestricted') : $t('admin.users.editDialog.canChangeIdentityHint')"
              persistent-hint class="mb-4" />

    <v-switch v-model="mustChangePassword" :label="$t('admin.users.mustChangePassword')" color="primary"
              :disabled="props.loading" :hint="$t('admin.users.editDialog.mustChangePasswordHint')" persistent-hint />
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {type UserDto, UserRole} from "~/utils/model";
import type {UpdateUserPayload} from "~/utils/api";
import {showSnackbar, userNameOrEmailError} from "~/utils/utils";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', payload: UpdateUserPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const isAdmin = ref(false);
const userName = ref('');
const email = ref('');
const canLogin = ref(true);
const canManageRepositories = ref(true);
const canChangeIdentity = ref(true);
const mustChangePassword = ref(false);

const submit = () => {
  const trimmedUserName = userName.value.trim();
  const trimmedEmail = email.value.trim();
  const error = userNameOrEmailError(trimmedUserName, trimmedEmail);
  if (error) {
    showSnackbar(error);
    return;
  }

  emit('submit', {
    user_name: trimmedUserName,
    email: trimmedEmail || null,
    can_login: canLogin.value,
    can_manage_repositories: canManageRepositories.value,
    can_change_identity: canChangeIdentity.value,
    must_change_password: mustChangePassword.value,
  });
}

defineExpose({
  reset: (user: UserDto) => {
    isAdmin.value = user.role === UserRole.ADMIN;
    userName.value = user.user_name;
    email.value = user.email ?? '';
    canLogin.value = user.can_login;
    canManageRepositories.value = user.can_manage_repositories;
    canChangeIdentity.value = user.can_change_identity;
    mustChangePassword.value = user.must_change_password;
  },
});
</script>
