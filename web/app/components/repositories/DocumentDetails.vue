<template>
  <div class="text-caption py-1">
    <template v-if="document.conversion?.status === DocumentConversionStatus.CONVERTING">
      <i18n-t scope="global" keypath="documents.details.started" tag="span">
        <template v-slot:relative>
          <span :title="formatDateTime(document.conversion.started_at)">{{ formatRelative(document.conversion.started_at) }}</span>
        </template>
      </i18n-t>
    </template>
    <template v-else-if="document.conversion?.status === DocumentConversionStatus.SKIPPED">
      <i18n-t scope="global" keypath="documents.details.skipped" tag="span">
        <template v-slot:reason>{{ skipReason(document.conversion.skip_reason) }}</template>
        <template v-slot:relative>
          <span :title="formatDateTime(document.conversion.retry_at)">{{ formatRelative(document.conversion.retry_at) }}</span>
        </template>
      </i18n-t>
    </template>
    <template v-else-if="document.conversion">
      <template v-if="document.extraction">
        {{ $t('documents.details.settingsChanged') }}
      </template>
      <template v-else>{{ $t('documents.details.new') }}</template>
    </template>
    <template v-else-if="document.extraction?.status === DocumentExtractionStatus.FAILED">
      {{ document.extraction.error }}
    </template>
    <template v-else-if="document.extraction">
      <span :title="formatDateTime(document.extraction.extracted_at)">
        {{ formatRelative(document.extraction.extracted_at) }}
      </span>
      <template v-if="document.extraction.ocr">
        • OCR
      </template>
    </template>
  </div>
</template>

<script setup lang="ts">
import {
  DocumentConversionStatus,
  DocumentExtractionStatus,
  DocumentSkipReason,
  type RepositoryDocumentDto,
} from "~/utils/model";
import {formatDateTime, formatRelative} from "~/utils/utils";
import {useI18n} from "#i18n";

defineProps<{
  document: RepositoryDocumentDto,
}>();

const {t} = useI18n();

const skipReason = (reason: DocumentSkipReason | null): string => {
  switch (reason) {
    case DocumentSkipReason.LFS_OBJECT_MISSING:
      return t('documents.details.lfsObjectMissing');
    default:
      return t('documents.details.unreadable');
  }
}
</script>
