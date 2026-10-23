<template>
  <MainContainer :title="$t('admin.extraction.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <template v-slot:meta>
      <p class="text-h6 mb-4" v-if="overview">
        {{ $t('admin.extraction.page.count', overview.totals.documents) }}
      </p>

      <p class="text-medium-emphasis">
        {{ $t('documents.description') }}
      </p>
      <i18n-t scope="global" keypath="admin.extraction.page.ocrSettings" tag="p" class="mt-2 text-medium-emphasis">
        <template v-slot:config>
          <NuxtLink to="/settings/admin/config">{{ $t('admin.extraction.page.configLink') }}</NuxtLink>
        </template>
      </i18n-t>
    </template>

    <v-progress-linear v-if="fetching && !overview" indeterminate color="primary"/>

    <template v-if="overview">
      <v-alert v-if="overview.paused" type="warning" variant="tonal" class="mb-6"
               :title="$t('admin.extraction.page.pausedTitle')">
        <i18n-t scope="global" keypath="admin.extraction.page.pausedUntil" tag="span">
          <template v-slot:time>
            <span :title="formatRelative(overview.paused.until)">{{ formatDateTime(overview.paused.until) }}</span>
          </template>
        </i18n-t>
        <div class="mt-2 text-caption" style="word-break: break-word">{{ overview.paused.reason }}</div>
      </v-alert>

      <v-card :title="$t('common.status')" prepend-icon="mdi-file-sync">
        <v-table>
          <tbody>
          <tr>
            <td style="width: 160px">{{ $t('admin.extraction.page.now') }}</td>
            <td>
              <i18n-t scope="global" v-if="overview.converting" :keypath="convertingKeypath(overview.converting)" tag="span">
                <template v-slot:path>
                  <code style="word-break: break-all">{{ overview.converting.path }}</code>
                </template>
                <template v-slot:repository>{{ overview.converting.repository?.name }}</template>
                <template v-slot:owner>{{ overview.converting.repository?.owner_name }}</template>
                <template v-slot:started>
                  <span :title="formatDateTime(overview.converting.started_at)">
                    {{ formatRelative(overview.converting.started_at) }}
                  </span>
                </template>
              </i18n-t>
              <template v-else-if="overview.paused">{{ $t('admin.extraction.page.statusPaused') }}</template>
              <template v-else-if="overview.totals.waiting > 0">{{ $t('admin.extraction.page.statusWaiting') }}</template>
              <template v-else>{{ $t('admin.extraction.page.statusIdle') }}</template>
            </td>
          </tr>
          <tr>
            <td>{{ $t('documents.title') }}</td>
            <td class="py-2">
              <div class="d-flex flex-wrap ga-2">
                <v-chip size="small" label>{{ $t('admin.extraction.page.total', {count: overview.totals.documents}) }}</v-chip>
                <v-chip size="small" label color="green">
                  {{ $t('admin.extraction.page.converted', {count: overview.totals.converted}) }}
                </v-chip>
                <v-chip size="small" label color="red">
                  {{ $t('admin.extraction.page.failed', {count: overview.totals.failed}) }}
                </v-chip>
                <v-chip size="small" label color="grey">
                  {{ $t('admin.extraction.page.waiting', {count: overview.totals.waiting}) }}
                </v-chip>
                <v-chip size="small" label color="orange">
                  {{ $t('admin.extraction.page.notAvailable', {count: overview.totals.skipped}) }}
                </v-chip>
              </div>
            </td>
          </tr>
          <tr>
            <td>{{ $t('admin.extraction.page.extractor') }}</td>
            <td><code style="word-break: break-all">{{ overview.extractor }}</code></td>
          </tr>
          </tbody>
        </v-table>
      </v-card>

      <v-card :title="$t('documents.title')" prepend-icon="mdi-file-document-multiple" class="mt-6">
        <v-card-text>
          <v-data-table-server
              v-model:page="page"
              v-model:items-per-page="itemsPerPage"
              :headers="[
                  { title: $t('common.repository'), key: 'repository', sortable: false },
                  { title: $t('documents.document'), key: 'path', sortable: false },
                  { title: $t('common.status'), key: 'status', sortable: false },
                  { title: $t('documents.detailsColumn'), key: 'details', sortable: false },
                  { title: '', key: 'actions', sortable: false, width: 60 },
              ]"
              :items="documents"
              :items-length="documentsTotal"
              :items-per-page-options="[10, 25, 50, 100]"
              :item-value="(item: ExtractionDocumentDto) => item.repository.id + '/' + item.path"
              :loading="fetchingDocuments"
              density="compact"
              :loading-text="$t('common.loading')"
              :no-data-text="$t('documents.noData')"
              @update:options="fetchDocuments(true)"
          >
            <template v-slot:item.repository="{ item }">
              <NuxtLink v-if="item.repository.readable" :to="'/settings/repositories/' + item.repository.id">
                {{ item.repository.name }}
              </NuxtLink>
              <span v-else>{{ item.repository.name }}</span>
            </template>

            <template v-slot:header.status="{ column }">
              {{ column.title }}
              <DocumentStatusFilter v-model="filter" :counts="{
                  all: overview.totals.documents,
                  converted: overview.totals.converted,
                  failed: overview.totals.failed,
                  pending: overview.totals.waiting + overview.totals.skipped,
              }"/>
            </template>

            <template v-slot:item.path="{ item }">
              <span style="word-break: break-all">{{ item.path }}</span>
            </template>

            <template v-slot:item.status="{ item }">
              <DocumentStatusChip :document="item"/>
            </template>

            <template v-slot:item.details="{ item }">
              <DocumentDetails :document="item"/>
            </template>

            <template v-slot:item.actions="{ item }">
              <v-btn v-if="canRetry(item)" @click="doRetry(item)" icon="mdi-restart" variant="text" size="small"
                     :loading="retrying === item.blob_oid" :disabled="retrying !== null"
                     v-tooltip="$t('admin.extraction.page.convertAgain')"/>
            </template>
          </v-data-table-server>
        </v-card-text>
      </v-card>
    </template>
  </MainContainer>
</template>

<script setup lang="ts">
import {onBeforeUnmount, onMounted, ref, watch} from "vue";
import {
  DocumentConversionStatus,
  DocumentExtractionStatus,
  DocumentFilter,
  type ConvertingDocumentDto,
  type ExtractionDocumentDto,
  type ExtractionOverviewDto,
} from "~/utils/model";
import {errorMessage, getExtractionDocuments, getExtractionOverview, retryDocument} from "~/utils/api";
import {formatDateTime, formatRelative, showSnackbar} from "~/utils/utils";
import {NuxtLink} from "#components";
import MainContainer from "~/components/MainContainer.vue";
import DocumentDetails from "~/components/repositories/DocumentDetails.vue";
import DocumentStatusChip from "~/components/repositories/DocumentStatusChip.vue";
import DocumentStatusFilter from "~/components/repositories/DocumentStatusFilter.vue";
import {useI18n} from "#i18n";

const {t} = useI18n();

// While documents are waiting, else only to notice new ones.
const ACTIVE_POLL_INTERVAL_MS = 5000;
const IDLE_POLL_INTERVAL_MS = 30000;

const fetching = ref(true);
const retrying = ref<string | null>(null);
const overview = ref<ExtractionOverviewDto | null>(null);

const filter = ref(DocumentFilter.ALL);
const page = ref(1);
const itemsPerPage = ref(25);
const fetchingDocuments = ref(false);
const documents = ref<ExtractionDocumentDto[]>([]);
const documentsTotal = ref(0);

const convertingKeypath = (converting: ConvertingDocumentDto): string => {
  if (converting.attachment) {
    return 'admin.extraction.page.convertingAttachment';
  }
  if (converting.repository) {
    return 'admin.extraction.page.convertingRepository';
  }
  return 'admin.extraction.page.converting';
}

/** Failed with the current settings, or not available for now. */
const canRetry = (document: ExtractionDocumentDto): boolean =>
    document.conversion?.status === DocumentConversionStatus.SKIPPED
    || (!document.conversion && document.extraction?.status === DocumentExtractionStatus.FAILED);

/** Quiet unless `reportErrors`, so failed polls are just retried. */
const fetchOverview = async (reportErrors: boolean) => {
  try {
    fetching.value = true;
    overview.value = await getExtractionOverview();
  } catch (e) {
    if (reportErrors) {
      showSnackbar(t('admin.extraction.page.loadFailed', {error: errorMessage(e)}));
    }
  } finally {
    fetching.value = false;
  }
}

/** The current page. Quiet unless `reportErrors`, like {@link fetchOverview}. */
const fetchDocuments = async (reportErrors: boolean) => {
  try {
    fetchingDocuments.value = true;
    const result = await getExtractionDocuments(
        filter.value, (page.value - 1) * itemsPerPage.value, itemsPerPage.value);
    documents.value = result.items;
    documentsTotal.value = result.total;
    // The page may be gone after documents were converted or removed.
    const lastPage = Math.max(1, Math.ceil(result.total / itemsPerPage.value));
    if (page.value > lastPage) {
      page.value = lastPage;
    }
  } catch (e) {
    if (reportErrors) {
      showSnackbar(t('admin.extraction.page.loadFailed', {error: errorMessage(e)}));
    }
  } finally {
    fetchingDocuments.value = false;
  }
}

watch(filter, () => {
  if (page.value === 1) {
    fetchDocuments(true);
  } else {
    // Fetched by `update:options`.
    page.value = 1;
  }
});

const doRetry = async (document: ExtractionDocumentDto) => {
  retrying.value = document.blob_oid;
  try {
    await retryDocument(document.blob_oid);
    showSnackbar(t('admin.extraction.page.retried'));
    await Promise.all([fetchOverview(true), fetchDocuments(true)]);
  } catch (e) {
    showSnackbar(t('admin.extraction.page.retryFailed', {error: errorMessage(e)}));
  } finally {
    retrying.value = null;
  }
}

let pollTimer: ReturnType<typeof setTimeout> | null = null;
let unmounted = false;

const schedulePoll = () => {
  if (unmounted) {
    return;
  }
  const active = !!overview.value?.converting || (overview.value?.totals.waiting ?? 0) > 0;
  pollTimer = setTimeout(async () => {
    await Promise.all([fetchOverview(false), fetchDocuments(false)]);
    schedulePoll();
  }, active ? ACTIVE_POLL_INTERVAL_MS : IDLE_POLL_INTERVAL_MS);
}

onMounted(async () => {
  // The documents are fetched by the table's `update:options` once it is shown.
  await fetchOverview(true);
  schedulePoll();
});

onBeforeUnmount(() => {
  unmounted = true;
  if (pollTimer !== null) {
    clearTimeout(pollTimer);
  }
});
</script>
