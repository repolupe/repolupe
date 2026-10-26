<template>
  <MainContainer :title="repository?.name ?? ''"
                 :parents="[{title: $t('settings.title'), to: '/settings'}, {title: $t('repositories.title'), to: '/settings/repositories'}]">
    <template v-slot:meta v-if="repository">
      <div style="max-width: 300px">
        <p v-if="isOwner" class="text-medium-emphasis">
          {{ repository.remote ? $t('repositories.page.ownerIntro') : $t('repositories.page.ownerIntroLocal') }}
        </p>
        <p v-else class="text-medium-emphasis">
          {{ $t('repositories.page.sharedIntro') }}
        </p>

        <div class="mt-6">
          <div class="meta-row">
            <span class="text-medium-emphasis">{{ $t('repositories.page.owner') }}</span>
            <span>{{ isOwner ? $t('repositories.page.ownerYou') : $t('repositories.page.ownerShared') }}</span>
          </div>
          <div class="meta-row">
            <span class="text-medium-emphasis">{{ $t('repositories.size') }}</span>
            <span :title="sizeTitle" class="text-right">
              {{ formatBytes(totalSize) }}
              <span v-if="repository.lfs_size" class="d-block text-caption text-medium-emphasis">
                {{ $t('repositories.page.sizeSplit', {git: formatBytes(repository.git_size), lfs: formatBytes(repository.lfs_size)}) }}
              </span>
            </span>
          </div>
          <div class="meta-row">
            <span class="text-medium-emphasis">{{ $t('repositories.page.created') }}</span>
            <span :title="formatDateTime(repository.created_at)">{{ formatRelative(repository.created_at) }}</span>
          </div>
        </div>

        <v-btn @click="navigateTo('/?repository=' + repository.id)" class="mt-6" color="primary"
               prepend-icon="mdi-message-question" :text="$t('repositories.page.askQuestion')" block/>
      </div>
    </template>

    <v-progress-linear v-if="fetching && !repository" indeterminate color="primary"/>

    <template v-if="repository">
      <v-alert v-if="repository.sync_status === RepositorySyncStatus.FAILED" type="error" variant="tonal"
               :title="$t('repositories.page.lastSyncFailed')" class="mb-6">
        {{ repository.last_error ?? $t('common.unknownError') }}
      </v-alert>

      <v-card :title="$t('common.repository')" prepend-icon="mdi-information">
        <v-table>
          <tbody>
          <tr>
            <td>{{ $t('common.name') }}</td>
            <td>{{ repository.name }}</td>
          </tr>
          <tr>
            <td>{{ $t('repositories.description') }}</td>
            <td style="white-space: pre-wrap">{{ repository.description ?? '-' }}</td>
          </tr>
          <template v-if="repository.remote">
            <tr>
              <td>{{ $t('repositories.remoteUrl') }}</td>
              <td style="word-break: break-all">{{ repository.remote.url }}</td>
            </tr>
            <tr>
              <td>{{ $t('repositories.branch') }}</td>
              <td>{{ repository.remote.branch }}</td>
            </tr>
            <tr>
              <td>{{ $t('repositories.accessToken') }}</td>
              <td>
                <template v-if="!repository.remote.token">{{ $t('repositories.page.tokenNone') }}</template>
                <template v-else>
                  {{ $t('repositories.page.tokenSet') }}
                  <span v-if="repository.remote.token.hint" class="ml-2 text-medium-emphasis">•••• {{ repository.remote.token.hint }}</span>
                </template>
              </td>
            </tr>
          </template>
          <tr v-else>
            <td>{{ $t('repositories.remote') }}</td>
            <td>{{ $t('repositories.page.remoteNone') }}</td>
          </tr>
          <tr>
            <td>{{ $t('repositories.page.writeAccess') }}</td>
            <td>{{ repository.can_commit ? $t('repositories.page.writeAccessEnabled') : $t('repositories.page.writeAccessDisabled') }}</td>
          </tr>
          </tbody>
        </v-table>
        <v-card-actions>
          <template v-if="isOwner">
            <v-btn @click="showEditDialog" prepend-icon="mdi-pencil" :text="$t('common.edit')"/>
            <v-btn @click="dialogDelete = true" prepend-icon="mdi-delete" :text="$t('common.delete')"/>
          </template>
          <v-btn v-else @click="dialogLeave = true" prepend-icon="mdi-logout" :text="$t('repositories.page.leave')"/>
        </v-card-actions>
      </v-card>

      <v-card :title="$t('repositories.page.sync')" prepend-icon="mdi-sync" class="mt-6">
        <v-table>
          <tbody>
          <tr>
            <td>{{ $t('common.status') }}</td>
            <td><SyncStatusChip :repository="repository"/></td>
          </tr>
          <tr>
            <td>{{ $t('repositories.page.interval') }}</td>
            <td>{{ repository.remote ? formatPollInterval(repository.remote.poll_interval_seconds) : $t('repositories.page.intervalLocal') }}</td>
          </tr>
          <tr>
            <td>{{ $t('repositories.page.headCommit') }}</td>
            <td :title="repository.head_commit_sha ?? ''" style="font-family: monospace">
              {{ shortSha(repository.head_commit_sha) }}
            </td>
          </tr>
          <tr>
            <td>{{ $t('repositories.page.lastSynced') }}</td>
            <td :title="formatDateTime(repository.last_synced_at)">{{ formatRelative(repository.last_synced_at) }}</td>
          </tr>
          <tr v-if="repository.sync_status === RepositorySyncStatus.SYNCING">
            <td>{{ $t('repositories.page.syncStarted') }}</td>
            <td :title="formatDateTime(repository.sync_started_at)">{{ formatRelative(repository.sync_started_at) }}</td>
          </tr>
          <tr>
            <td>{{ $t('repositories.page.nextSync') }}</td>
            <td :title="formatDateTime(repository.next_sync_at)">{{ formatRelative(repository.next_sync_at) }}</td>
          </tr>
          </tbody>
        </v-table>
        <!-- A local repository is synced after each commit, there is nothing else to fetch. -->
        <v-card-actions v-if="isOwner && repository.remote">
          <v-btn @click="doRequestSync" :loading="syncing" color="primary" variant="elevated" prepend-icon="mdi-sync"
                 :text="$t('repositories.page.syncNow')"/>
        </v-card-actions>
      </v-card>

      <RepositoryDocumentsCard :repository-id="repository.id" :head-commit-sha="repository.head_commit_sha"
                               class="mt-6"/>

      <RepositoryUsersCard v-if="canManageSharing" :repository-id="repository.id" :allow-commits="repository.allow_commits"
                           :local="!repository.remote" class="mt-6"/>
    </template>

    <EditRepositoryDialog ref="edit-dialog" v-model="dialogEdit" :loading="loading" @submit="doUpdate"/>

    <GenericDeleteDialog v-model="dialogDelete" :loading="loading" :title="$t('repositories.page.deleteTitle')"
                         :verify="repository?.name" @delete="doDelete">
      {{ repository?.remote === null ? $t('repositories.page.deleteTextLocal') : $t('repositories.page.deleteText') }}
    </GenericDeleteDialog>

    <GenericConfirmDialog v-model="dialogLeave" :loading="loading" :title="$t('repositories.page.leaveTitle')"
                          :confirm-text="$t('repositories.page.leave')" confirm-icon="mdi-logout" @confirm="doLeave">
      {{ $t('repositories.page.leaveText') }}
    </GenericConfirmDialog>
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, onMounted, ref, useTemplateRef} from "vue";
import {navigateTo, useRoute} from "#app";
import {ErrorCode, type RepositoryDto, RepositorySyncStatus, UserRole} from "~/utils/model";
import {
  ApiError,
  deleteRepository,
  errorMessage,
  getRepository,
  removeRepositoryUser,
  requestSync,
  updateRepository,
  type UpdateRepositoryPayload,
} from "~/utils/api";
import {
  formatBytes,
  formatDateTime,
  formatPollInterval,
  formatRelative,
  repositorySize,
  shortSha,
  showSnackbar,
} from "~/utils/utils";
import {useUser} from "~/composables/states";
import MainContainer from "~/components/MainContainer.vue";
import SyncStatusChip from "~/components/SyncStatusChip.vue";
import GenericDeleteDialog from "~/components/dialogs/GenericDeleteDialog.vue";
import EditRepositoryDialog from "~/components/repositories/EditRepositoryDialog.vue";
import RepositoryDocumentsCard from "~/components/repositories/RepositoryDocumentsCard.vue";
import RepositoryUsersCard from "~/components/repositories/RepositoryUsersCard.vue";
import GenericConfirmDialog from "~/components/dialogs/GenericConfirmDialog.vue";
import {useI18n} from "#i18n";

const POLL_INTERVAL_MS = 5000;
// A requested sync only makes the repository due, the scheduler picks it up within a few seconds.
const SYNC_REQUEST_POLL_MS = 30000;

const {t} = useI18n();

const route = useRoute();
const user = useUser();
const id = computed(() => route.params.id as string);

const editDialog = useTemplateRef<InstanceType<typeof EditRepositoryDialog>>('edit-dialog');

const fetching = ref(true);
const loading = ref(false);
const syncing = ref(false);
const repository = ref<RepositoryDto | null>(null);

const dialogEdit = ref(false);
const dialogDelete = ref(false);
const dialogLeave = ref(false);

// Only the owner may update, delete or sync; the others get FORBIDDEN.
const isOwner = computed(() => !!repository.value && repository.value.owner_id === user.value?.id);
// Admins may manage the sharing of any repository they can see.
const canManageSharing = computed(() => isOwner.value || user.value?.role === UserRole.ADMIN);

const totalSize = computed(() => repository.value ? repositorySize(repository.value) : null);
const sizeTitle = computed(() => {
  const r = repository.value;
  if (totalSize.value === null || !r?.remote) {
    return '';
  }
  return t('repositories.page.sizeTitle', {branch: r.remote.branch});
});

const handleNotFound = (e: unknown): boolean => {
  if (e instanceof ApiError && e.code === ErrorCode.NOT_FOUND) {
    showSnackbar(t('repositories.page.notFound'));
    navigateTo('/settings/repositories');
    return true;
  }
  return false;
}

const fetchData = async () => {
  try {
    fetching.value = true;
    repository.value = await getRepository(id.value);
  } catch (e) {
    if (!handleNotFound(e)) {
      showSnackbar(t('repositories.page.loadFailed', {error: errorMessage(e)}));
    }
  } finally {
    fetching.value = false;
  }
}

// --- Polling while a sync is pending or running ---

let pollTimer: ReturnType<typeof setInterval> | null = null;
let polling = false;
let pollUntil = 0;
let unmounted = false;

const needsPolling = () => {
  const status = repository.value?.sync_status;
  return status === RepositorySyncStatus.PENDING
      || status === RepositorySyncStatus.SYNCING
      || Date.now() < pollUntil;
}

const poll = async () => {
  if (polling || fetching.value || !repository.value || !needsPolling()) {
    return;
  }
  polling = true;
  try {
    repository.value = await getRepository(id.value);
  } catch (e) {
    // Quiet: transient errors are retried on the next tick.
    if (handleNotFound(e)) {
      stopPolling();
    }
  } finally {
    polling = false;
  }
}

const stopPolling = () => {
  if (pollTimer !== null) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

// --- Actions ---

const doRequestSync = async () => {
  syncing.value = true;
  try {
    await requestSync(id.value);
    pollUntil = Date.now() + SYNC_REQUEST_POLL_MS;
    showSnackbar(t('repositories.page.syncRequested'));
    await fetchData();
  } catch (e) {
    showSnackbar(t('repositories.page.syncFailed', {error: errorMessage(e)}));
  } finally {
    syncing.value = false;
  }
}

const showEditDialog = () => {
  editDialog.value!.load(repository.value!);
  dialogEdit.value = true;
}

const doUpdate = async (payload: UpdateRepositoryPayload) => {
  loading.value = true;
  try {
    repository.value = await updateRepository(id.value, payload);
    dialogEdit.value = false;
    showSnackbar(t('repositories.page.updated'));
  } catch (e) {
    // The dialog stays open, so the input can be corrected.
    showSnackbar(t('repositories.page.saveFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

const doDelete = async () => {
  loading.value = true;
  try {
    await deleteRepository(id.value);
    dialogDelete.value = false;
    showSnackbar(t('repositories.page.deleted'));
    await navigateTo('/settings/repositories');
  } catch (e) {
    showSnackbar(t('repositories.page.deleteFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

const doLeave = async () => {
  loading.value = true;
  try {
    await removeRepositoryUser(id.value, user.value!.id);
    dialogLeave.value = false;
    showSnackbar(t('repositories.page.left'));
    await navigateTo('/settings/repositories');
  } catch (e) {
    showSnackbar(t('repositories.page.leaveFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

onMounted(async () => {
  await fetchData();
  if (!unmounted) {
    pollTimer = setInterval(poll, POLL_INTERVAL_MS);
  }
});

onBeforeUnmount(() => {
  unmounted = true;
  stopPolling();
});
</script>

<style scoped>
.meta-row {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  padding: 4px 0;
}
</style>
