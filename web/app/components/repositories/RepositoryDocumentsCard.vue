<template>
  <v-card v-if="documents.length > 0" :title="$t('documents.title')" prepend-icon="mdi-file-document-multiple">
    <v-card-text class="text-medium-emphasis">
      {{ $t('documents.description') }}
    </v-card-text>

    <v-card-text class="pt-0">
      <v-alert v-if="pausedUntil && counts.pending > 0" type="warning" variant="tonal" density="compact" class="mb-4">
        <i18n-t scope="global" keypath="documents.card.paused" tag="span">
          <template v-slot:time>
            <span :title="formatRelative(pausedUntil)">{{ formatDateTime(pausedUntil) }}</span>
          </template>
        </i18n-t>
      </v-alert>

      <v-data-table
          :headers="[
              { title: $t('documents.document'), key: 'path', sortable: true },
              { title: $t('common.status'), key: 'status', sortable: false },
              { title: $t('documents.detailsColumn'), key: 'details', sortable: false },
          ]"
          :items="documentsFiltered"
          item-value="path"
          :items-per-page="10"
          density="compact"
          :no-data-text="$t('documents.noData')"
      >
        <template v-slot:header.status="{ column }">
          {{ column.title }}
          <DocumentStatusFilter v-model="filter" :counts="counts"/>
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
      </v-data-table>
    </v-card-text>
  </v-card>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, onMounted, ref, watch} from "vue";
import {DocumentExtractionStatus, DocumentFilter, type RepositoryDocumentDto} from "~/utils/model";
import {errorMessage, getRepositoryDocuments} from "~/utils/api";
import {formatDateTime, formatRelative, showSnackbar} from "~/utils/utils";
import DocumentDetails from "~/components/repositories/DocumentDetails.vue";
import DocumentStatusChip from "~/components/repositories/DocumentStatusChip.vue";
import DocumentStatusFilter from "~/components/repositories/DocumentStatusFilter.vue";
import {useI18n} from "#i18n";

const {t} = useI18n();

const props = defineProps<{
  repositoryId: string,
  /** Refetched when a sync changes it, since the documents are those of this commit. */
  headCommitSha: string | null,
}>();

// While documents are pending. Conversions take seconds to minutes each.
const POLL_INTERVAL_MS = 5000;

const documents = ref<RepositoryDocumentDto[]>([]);
const pausedUntil = ref<string | null>(null);
const filter = ref(DocumentFilter.ALL);

const category = (document: RepositoryDocumentDto): DocumentFilter => {
  if (document.conversion) {
    return DocumentFilter.PENDING;
  }
  return document.extraction?.status === DocumentExtractionStatus.FAILED ? DocumentFilter.FAILED : DocumentFilter.CONVERTED;
}

const counts = computed(() => {
  const counts = {all: documents.value.length, converted: 0, failed: 0, pending: 0};
  for (const document of documents.value) {
    switch (category(document)) {
      case DocumentFilter.CONVERTED:
        counts.converted++;
        break;
      case DocumentFilter.FAILED:
        counts.failed++;
        break;
      case DocumentFilter.PENDING:
        counts.pending++;
        break;
    }
  }
  return counts;
});

const documentsFiltered = computed(() => filter.value === DocumentFilter.ALL
    ? documents.value
    : documents.value.filter(document => category(document) === filter.value));

let fetching = false;

/** Quiet unless `reportErrors`, so failed polls are just retried. */
const fetchData = async (reportErrors: boolean) => {
  if (fetching) {
    return;
  }
  fetching = true;
  try {
    const result = await getRepositoryDocuments(props.repositoryId);
    documents.value = result.documents;
    pausedUntil.value = result.paused_until;
  } catch (e) {
    if (reportErrors) {
      showSnackbar(t('documents.loadFailed', {error: errorMessage(e)}));
    }
  } finally {
    fetching = false;
  }
}

let pollTimer: ReturnType<typeof setInterval> | null = null;

const poll = async () => {
  if (counts.value.pending > 0) {
    await fetchData(false);
  }
}

watch(() => props.headCommitSha, () => fetchData(false));

onMounted(async () => {
  await fetchData(true);
  pollTimer = setInterval(poll, POLL_INTERVAL_MS);
});

onBeforeUnmount(() => {
  if (pollTimer !== null) {
    clearInterval(pollTimer);
  }
});
</script>
