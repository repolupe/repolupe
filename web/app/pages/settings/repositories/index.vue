<template>
  <MainContainer :title="$t('repositories.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <template v-slot:meta>
      <p class="text-h6 mb-4">{{ $t('repositories.listPage.count', repositories.length) }}</p>

      <p class="text-medium-emphasis">
        {{ $t('repositories.listPage.description') }}
      </p>

      <v-btn @click="showCreateDialog" class="mt-6" color="primary" prepend-icon="mdi-plus" :text="$t('repositories.newRepository')" block />
    </template>

    <EmptyState v-if="!fetching && repositories.length === 0" icon="mdi-source-repository"
                :title="$t('repositories.listPage.emptyTitle')" :action-text="$t('repositories.newRepository')" @action="showCreateDialog">
      {{ $t('repositories.listPage.emptyText') }}
    </EmptyState>

    <template v-else>
      <SearchField v-model="query" />

      <v-card class="mt-10">
        <v-card-text class="pb-0">
          <v-data-table
              :loading="fetching"
              :headers="[
                  { title: $t('common.name'), key: 'name', sortable: true },
                  { title: $t('repositories.remote'), key: 'remote', value: (r: RepositoryDto) => r.remote?.url ?? '', sortable: true },
                  { title: $t('repositories.size'), key: 'size', value: (r: RepositoryDto) => repositorySize(r) ?? -1, sortable: true },
                  { title: $t('common.status'), key: 'sync_status', sortable: true },
              ]"
              :items="repositoriesFiltered"
              :items-per-page="50"
              :row-props="{ style: 'cursor: pointer' }"
              hover
              :loading-text="$t('common.loading')"
              :no-data-text="$t('repositories.listPage.noMatch')"
              @click:row="onRowClick"
          >
            <template v-slot:item.remote="{ item }">
              <div v-if="item.remote" class="d-flex text-caption">
                <span class="remote-url" :title="item.remote.url">{{ item.remote.url }}</span>
                <span class="ml-1 text-no-wrap">({{ item.remote.branch }})</span>
              </div>
              <div v-else class="d-flex align-center text-caption text-medium-emphasis">
                <v-icon size="small" class="mr-1">mdi-server</v-icon>
                {{ $t('repositories.local') }}
              </div>
            </template>

            <template v-slot:item.size="{ item }">
              <span class="text-no-wrap">{{ formatBytes(repositorySize(item)) }}</span>
            </template>

            <template v-slot:item.sync_status="{ item }">
              <SyncStatusChip :repository="item" />
            </template>
          </v-data-table>
        </v-card-text>
      </v-card>
    </template>

    <RepositoryKindDialog v-model="dialogKind" @select="selectKind" />
    <CreateRepositoryDialog ref="create-dialog" v-model="dialogCreate" :loading="loading" @submit="doCreate" />
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, onMounted, ref, useTemplateRef} from "vue";
import {navigateTo} from "#app";
import {type RepositoryDto, RepositorySyncStatus} from "~/utils/model";
import {createRepository, type CreateRepositoryPayload, errorMessage, getRepositories} from "~/utils/api";
import {formatBytes, repositorySize, showSnackbar} from "~/utils/utils";
import MainContainer from "~/components/MainContainer.vue";
import EmptyState from "~/components/EmptyState.vue";
import SearchField from "~/components/SearchField.vue";
import SyncStatusChip from "~/components/SyncStatusChip.vue";
import CreateRepositoryDialog from "~/components/repositories/CreateRepositoryDialog.vue";
import RepositoryKindDialog, {type RepositoryKind} from "~/components/repositories/RepositoryKindDialog.vue";
import {useI18n} from "#i18n";

const POLL_INTERVAL_MS = 5000;

const {t} = useI18n();

const createDialog = useTemplateRef<InstanceType<typeof CreateRepositoryDialog>>('create-dialog');

const fetching = ref(true);
const loading = ref(false);
const repositories = ref<RepositoryDto[]>([]);
const query = ref('');
const dialogKind = ref(false);
const dialogCreate = ref(false);

let pollTimer: ReturnType<typeof setTimeout> | null = null;
let unmounted = false;

const repositoriesFiltered = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) {
    return repositories.value;
  }
  return repositories.value.filter(r =>
      r.name.toLowerCase().includes(q)
      || (r.remote?.url.toLowerCase().includes(q) ?? false)
      || (r.description?.toLowerCase().includes(q) ?? false));
});

const isSyncing = (repository: RepositoryDto) =>
    repository.sync_status === RepositorySyncStatus.PENDING
    || repository.sync_status === RepositorySyncStatus.SYNCING;

const stopPolling = () => {
  if (pollTimer !== null) {
    clearTimeout(pollTimer);
    pollTimer = null;
  }
}

/** Re-fetches quietly while a repository is waiting for or in a sync. */
const schedulePoll = () => {
  stopPolling();
  if (unmounted || !repositories.value.some(isSyncing)) {
    return;
  }
  pollTimer = setTimeout(() => fetchData(true), POLL_INTERVAL_MS);
}

/** `quiet` keeps the table from showing the loading state and errors from showing a snackbar. */
const fetchData = async (quiet = false) => {
  try {
    if (!quiet) {
      fetching.value = true;
    }
    repositories.value = await getRepositories();
  } catch (e) {
    if (!quiet) {
      showSnackbar(t('repositories.listPage.loadFailed', {error: errorMessage(e)}));
    }
  } finally {
    fetching.value = false;
    schedulePoll();
  }
}

const onRowClick = (_: Event, row: { item: RepositoryDto }) => {
  navigateTo(`/settings/repositories/${row.item.id}`);
}

const showCreateDialog = () => {
  dialogKind.value = true;
}

const selectKind = (kind: RepositoryKind) => {
  dialogKind.value = false;
  createDialog.value!.reset(kind);
  dialogCreate.value = true;
}

const doCreate = async (payload: CreateRepositoryPayload) => {
  loading.value = true;
  try {
    await createRepository(payload);
    dialogCreate.value = false;
    showSnackbar(t('repositories.listPage.added'));
    await fetchData(true);
  } catch (e) {
    showSnackbar(t('repositories.listPage.createFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

onMounted(async () => {
  await fetchData();
});

onBeforeUnmount(() => {
  unmounted = true;
  stopPolling();
});
</script>

<style scoped>
.remote-url {
  max-width: 280px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
