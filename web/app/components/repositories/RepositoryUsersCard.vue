<template>
  <v-card :title="$t('repositories.usersCard.title')" prepend-icon="mdi-account-multiple">
    <v-card-text class="text-medium-emphasis">
      {{ props.local ? $t('repositories.usersCard.descriptionLocal') : $t('repositories.usersCard.description') }}
    </v-card-text>

    <v-card-text class="pt-0">
      <v-data-table
          :loading="fetching"
          :headers="[
              { title: $t('repositories.usersCard.user'), key: 'user_name', sortable: true },
              { title: $t('repositories.usersCard.sharedAt'), key: 'created_at', sortable: true },
              { title: $t('repositories.usersCard.canCommit'), key: 'can_commit', sortable: true },
              { title: $t('common.actions'), key: 'actions', sortable: false, width: 60 },
          ]"
          :items="users"
          item-value="user_id"
          :items-per-page="10"
          :hide-default-footer="users.length <= 10"
          density="compact"
          :loading-text="$t('common.loading')"
          :no-data-text="$t('repositories.usersCard.notShared')"
      >
        <template v-slot:item.user_name="{ item }">
          <div class="py-2">
            <div>{{ item.user_name }}</div>
            <div v-if="item.email" class="text-caption text-medium-emphasis">{{ item.email }}</div>
          </div>
        </template>

        <template v-slot:item.created_at="{ item }">
          <span :title="formatDateTime(item.created_at)">{{ formatRelative(item.created_at) }}</span>
        </template>

        <template v-slot:item.can_commit="{ item }">
          <div :title="allowCommits ? '' : $t('repositories.usersCard.canCommitOff')">
            <v-switch :model-value="item.can_commit" @update:model-value="doSetCanCommit(item, !!$event)"
                      :disabled="!allowCommits" :loading="updating === item.user_id"
                      color="primary" density="compact" hide-details/>
          </div>
        </template>

        <template v-slot:item.actions="{ item }">
          <v-btn @click="showRemoveDialog(item)" icon="mdi-account-remove" variant="text" size="small" :title="$t('repositories.usersCard.stopSharing')"/>
        </template>
      </v-data-table>
    </v-card-text>

    <v-card-actions>
      <v-btn @click="showShareDialog" color="primary" variant="elevated" prepend-icon="mdi-share-variant" :text="$t('repositories.share')"/>
    </v-card-actions>

    <ShareRepositoryDialog ref="share-dialog" v-model="dialogShare" :loading="loading" @submit="doShare"/>

    <GenericConfirmDialog v-model="dialogRemove" :loading="loading" :title="$t('repositories.usersCard.stopSharingTitle')"
                          :confirm-text="$t('repositories.usersCard.stopSharing')" confirm-icon="mdi-account-remove" @confirm="doRemove">
      <i18n-t scope="global" keypath="repositories.usersCard.stopSharingText" tag="span">
        <template v-slot:name>
          <strong>{{ selectedUser?.user_name }}</strong>
        </template>
      </i18n-t>
    </GenericConfirmDialog>
  </v-card>
</template>

<script setup lang="ts">
import {onMounted, ref, useTemplateRef} from "vue";
import {ErrorCode, type RepositoryUserDto} from "~/utils/model";
import {addRepositoryUser, ApiError, errorMessage, getRepositoryUsers, removeRepositoryUser, updateRepositoryUser} from "~/utils/api";
import {formatDateTime, formatRelative, showSnackbar} from "~/utils/utils";
import ShareRepositoryDialog from "~/components/repositories/ShareRepositoryDialog.vue";
import GenericConfirmDialog from "~/components/dialogs/GenericConfirmDialog.vue";
import {useI18n} from "#i18n";

const props = defineProps<{
  repositoryId: string,
  // Users can only commit to repositories that allow commits.
  allowCommits: boolean,
  // A local repository has no access token, its commits only move the branch on the server.
  local: boolean,
}>();

const {t} = useI18n();

const shareDialog = useTemplateRef<InstanceType<typeof ShareRepositoryDialog>>('share-dialog');

const fetching = ref(true);
const loading = ref(false);
const updating = ref<string | null>(null);
const users = ref<RepositoryUserDto[]>([]);
const selectedUser = ref<RepositoryUserDto | null>(null);

const dialogShare = ref(false);
const dialogRemove = ref(false);

const fetchData = async () => {
  try {
    fetching.value = true;
    users.value = await getRepositoryUsers(props.repositoryId);
  } catch (e) {
    showSnackbar(t('repositories.usersCard.loadFailed', {error: errorMessage(e)}));
  } finally {
    fetching.value = false;
  }
}

const showShareDialog = () => {
  shareDialog.value!.reset();
  dialogShare.value = true;
}

const doShare = async (userNameOrEmail: string) => {
  loading.value = true;
  try {
    await addRepositoryUser(props.repositoryId, userNameOrEmail);
    dialogShare.value = false;
    await fetchData();
    showSnackbar(t('repositories.usersCard.shared'));
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_USER) {
      showSnackbar(t('repositories.usersCard.unknownUser'));
    } else {
      showSnackbar(t('repositories.usersCard.shareFailed', {error: errorMessage(e)}));
    }
  } finally {
    loading.value = false;
  }
}

const doSetCanCommit = async (user: RepositoryUserDto, canCommit: boolean) => {
  updating.value = user.user_id;
  try {
    await updateRepositoryUser(props.repositoryId, user.user_id, canCommit);
    user.can_commit = canCommit;
  } catch (e) {
    showSnackbar(t('repositories.usersCard.canCommitFailed', {error: errorMessage(e)}));
  } finally {
    updating.value = null;
  }
}

const showRemoveDialog = (user: RepositoryUserDto) => {
  selectedUser.value = user;
  dialogRemove.value = true;
}

const doRemove = async () => {
  loading.value = true;
  try {
    await removeRepositoryUser(props.repositoryId, selectedUser.value!.user_id);
    dialogRemove.value = false;
    await fetchData();
    showSnackbar(t('repositories.usersCard.stopped'));
  } catch (e) {
    showSnackbar(t('repositories.usersCard.stopFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

onMounted(async () => {
  await fetchData();
});
</script>
