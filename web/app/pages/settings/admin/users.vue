<template>
  <MainContainer :title="$t('admin.users.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <template v-slot:meta>
      <p class="text-h6 mb-4">{{ $t('admin.users.page.count', users.length) }}</p>

      <p class="text-medium-emphasis">
        {{ $t('admin.users.page.description') }}
      </p>

      <v-btn @click="showCreateUserDialog" class="mt-6" color="primary" prepend-icon="mdi-plus" :text="$t('admin.users.page.newUser')"
             block />
    </template>

    <SearchField v-model="query" />

    <v-card class="mt-10">
      <v-card-text class="pb-0">
        <v-data-table
            :loading="fetching"
            :headers="[
                { title: $t('admin.users.page.user'), key: 'user_name', sortable: true },
                { title: $t('user.role'), key: 'role', sortable: true },
                { title: $t('common.repository'), key: 'can_manage_repositories', sortable: true },
                { title: $t('admin.users.page.identity'), key: 'can_change_identity', sortable: true },
                { title: $t('common.actions'), key: 'actions', sortable: false, width: 200 },
            ]"
            :items="usersFiltered"
            :items-per-page="50"
            :loading-text="$t('common.loading')"
            :no-data-text="$t('admin.users.page.noUsers')"
        >
          <template v-slot:item.user_name="{ item }">
            <div class="py-2">
              <div>{{ item.user_name }}</div>
              <div v-if="item.email" class="text-caption text-medium-emphasis">{{ item.email }}</div>
              <div v-if="item.full_name" class="text-caption text-medium-emphasis">{{ item.full_name }}</div>
              <div v-if="!item.can_login" class="text-caption text-error">{{ $t('admin.users.page.loginDisabled') }}</div>
              <div v-if="item.must_change_password" class="text-caption text-warning">{{ $t('admin.users.page.passwordChangeRequired') }}</div>
            </div>
          </template>

          <template v-slot:item.role="{ item }">
            <v-chip v-if="item.role === UserRole.ADMIN" color="primary" size="small" prepend-icon="mdi-shield-account"
                    :text="$t('user.roleAdmin')" />
            <v-chip v-else size="small" :text="$t('user.roleUser')" />
          </template>

          <template v-slot:item.can_manage_repositories="{ item }">
            <v-chip v-if="item.can_manage_repositories" size="small" prepend-icon="mdi-check" :text="$t('admin.users.page.manage')" />
            <v-chip v-else size="small" prepend-icon="mdi-eye" :text="$t('admin.users.page.readOnly')" />
          </template>

          <template v-slot:item.can_change_identity="{ item }">
            <v-chip v-if="item.can_change_identity" size="small" prepend-icon="mdi-check" :text="$t('admin.users.page.editable')" />
            <v-chip v-else size="small" prepend-icon="mdi-account-lock" :text="$t('admin.users.page.fixed')" />
          </template>

          <template v-slot:item.actions="{ item }">
            <v-btn @click="showEditUserDialog(item)" icon="mdi-pencil" variant="text" />

            <v-tooltip :text="item.id === currentUser?.id ? $t('admin.users.page.cannotSetOwnPassword') : $t('admin.users.page.setPassword')"
                       location="top">
              <template v-slot:activator="{ props }">
                <!-- disabled buttons get no pointer events, so the tooltip hangs on a wrapper -->
                <span v-bind="props">
                  <v-btn @click="showPasswordDialog(item)" icon="mdi-key" variant="text"
                         :disabled="item.id === currentUser?.id" />
                </span>
              </template>
            </v-tooltip>

            <v-tooltip v-if="deleteBlockedReason(item)" :text="deleteBlockedReason(item)!" location="top">
              <template v-slot:activator="{ props }">
                <!-- disabled buttons get no pointer events, so the tooltip hangs on a wrapper -->
                <span v-bind="props">
                  <v-btn icon="mdi-delete" variant="text" disabled />
                </span>
              </template>
            </v-tooltip>
            <v-btn v-else @click="showDeleteUserDialog(item)" icon="mdi-delete" variant="text" />
          </template>
        </v-data-table>
      </v-card-text>
    </v-card>

    <CreateUserDialog ref="create-user-dialog" v-model="dialogCreateUser" :loading="loading" @submit="doCreateUser" />
    <EditUserDialog ref="edit-user-dialog" v-model="dialogEditUser" :loading="loading" @submit="doEditUser" />
    <SetPasswordDialog ref="password-dialog" v-model="dialogPassword" :loading="loading"
                       :user-name="selectedUser?.user_name ?? ''" @submit="doSetPassword" />
    <DeleteUserDialog v-model="dialogDeleteUser" :loading="loading" :user-name="selectedUser?.user_name ?? ''"
                      @delete="doDeleteUser" />
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, onMounted, ref, useTemplateRef} from "vue";
import {ErrorCode, type UserDto, UserRole} from "~/utils/model";
import {showSnackbar} from "~/utils/utils";
import {
  ApiError,
  deleteUser,
  errorMessage,
  getUsers,
  registerUser,
  type RegisterUserPayload,
  resetUserPassword,
  type ResetPasswordPayload,
  updateUser,
  type UpdateUserPayload,
} from "~/utils/api";
import {refreshUser, useUser} from "~/composables/states";
import {useI18n} from "#i18n";
import MainContainer from "~/components/MainContainer.vue";
import SearchField from "~/components/SearchField.vue";
import CreateUserDialog from "~/components/admin-users/CreateUserDialog.vue";
import DeleteUserDialog from "~/components/admin-users/DeleteUserDialog.vue";
import EditUserDialog from "~/components/admin-users/EditUserDialog.vue";
import SetPasswordDialog from "~/components/admin-users/SetPasswordDialog.vue";

const createUserDialog = useTemplateRef<InstanceType<typeof CreateUserDialog>>('create-user-dialog');
const editUserDialog = useTemplateRef<InstanceType<typeof EditUserDialog>>('edit-user-dialog');
const passwordDialog = useTemplateRef<InstanceType<typeof SetPasswordDialog>>('password-dialog');

const {t} = useI18n();

const currentUser = useUser();

const fetching = ref(true);
const loading = ref(false);
const users = ref<UserDto[]>([]);
const query = ref('');
const selectedUser = ref<UserDto | null>(null);

const dialogCreateUser = ref(false);
const dialogEditUser = ref(false);
const dialogPassword = ref(false);
const dialogDeleteUser = ref(false);

const usersFiltered = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) {
    return users.value;
  }
  return users.value.filter(u => [u.user_name, u.email, u.full_name].some(v => v?.toLowerCase().includes(q)));
});

/** Why the API would reject deleting this user, `null` if it can be deleted. */
const deleteBlockedReason = (user: UserDto): string | null => {
  if (user.id === currentUser.value?.id) {
    return t('admin.users.page.cannotDeleteSelf');
  }
  if (user.role === UserRole.ADMIN) {
    return t('admin.users.page.cannotDeleteAdmin');
  }
  return null;
}

const fetchData = async () => {
  try {
    fetching.value = true;
    users.value = await getUsers();
  } catch (e) {
    showSnackbar(t('admin.users.page.loadFailed', {error: errorMessage(e)}));
  } finally {
    fetching.value = false;
  }
}

const showCreateUserDialog = () => {
  createUserDialog.value!.reset();
  dialogCreateUser.value = true;
}

const showEditUserDialog = (user: UserDto) => {
  selectedUser.value = user;
  editUserDialog.value!.reset(user);
  dialogEditUser.value = true;
}

const showPasswordDialog = (user: UserDto) => {
  selectedUser.value = user;
  passwordDialog.value!.reset();
  dialogPassword.value = true;
}

const showDeleteUserDialog = (user: UserDto) => {
  selectedUser.value = user;
  dialogDeleteUser.value = true;
}

/** `failedKey` is the text for errors other than a taken user name or email, with the message as `error`. */
const showUserError = (e: unknown, failedKey: string) => {
  if (e instanceof ApiError && e.code === ErrorCode.USER_NAME_TAKEN) {
    showSnackbar(t('user.userNameTaken'));
  } else if (e instanceof ApiError && e.code === ErrorCode.EMAIL_TAKEN) {
    showSnackbar(t('user.emailTaken'));
  } else {
    showSnackbar(t(failedKey, {error: errorMessage(e)}));
  }
}

const doCreateUser = async (payload: RegisterUserPayload) => {
  loading.value = true;
  try {
    await registerUser(payload);
    dialogCreateUser.value = false;
    await fetchData();
    showSnackbar(t('admin.users.page.created'));
  } catch (e) {
    showUserError(e, 'admin.users.page.createFailed');
  } finally {
    loading.value = false;
  }
}

const doEditUser = async (payload: UpdateUserPayload) => {
  loading.value = true;
  try {
    const user = await updateUser(selectedUser.value!.id, payload);
    dialogEditUser.value = false;
    if (user.id === currentUser.value?.id) {
      // the navigation shows the own user name
      await refreshUser();
      if (currentUser.value?.must_change_password) {
        // app.vue logs them out, the API rejects everything else until the password is changed
        return;
      }
    }
    await fetchData();
    showSnackbar(t('admin.users.page.updated'));
  } catch (e) {
    showUserError(e, 'admin.users.page.saveFailed');
  } finally {
    loading.value = false;
  }
}

const doSetPassword = async (payload: ResetPasswordPayload) => {
  loading.value = true;
  try {
    await resetUserPassword(selectedUser.value!.id, payload);
    dialogPassword.value = false;
    await fetchData();
    showSnackbar(t('admin.users.page.passwordSet'));
  } catch (e) {
    showSnackbar(t('admin.users.page.setPasswordFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

const doDeleteUser = async () => {
  loading.value = true;
  try {
    await deleteUser(selectedUser.value!.id);
    dialogDeleteUser.value = false;
    await fetchData();
    showSnackbar(t('admin.users.page.deleted'));
  } catch (e) {
    showSnackbar(t('admin.users.page.deleteFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

onMounted(async () => {
  await fetchData();
});
</script>
