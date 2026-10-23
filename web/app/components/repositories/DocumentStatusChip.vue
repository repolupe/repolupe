<template>
  <v-chip :color="info.color" :prepend-icon="info.icon" size="small" label>
    {{ info.label }}
  </v-chip>
</template>

<script setup lang="ts">
import {computed} from "vue";
import {DocumentConversionStatus, DocumentExtractionStatus, type RepositoryDocumentDto} from "~/utils/model";
import {useI18n} from "#i18n";

const props = defineProps<{
  document: RepositoryDocumentDto,
}>();

const {t} = useI18n();

const info = computed(() => {
  switch (props.document.conversion?.status) {
    case DocumentConversionStatus.WAITING:
      return {label: t('status.waiting'), color: 'grey', icon: 'mdi-clock-outline'};
    case DocumentConversionStatus.CONVERTING:
      return {label: t('status.converting'), color: 'blue', icon: 'mdi-file-sync'};
    case DocumentConversionStatus.SKIPPED:
      return {label: t('status.notAvailable'), color: 'orange', icon: 'mdi-alert'};
  }
  if (props.document.extraction?.status === DocumentExtractionStatus.FAILED) {
    return {label: t('status.failed'), color: 'red', icon: 'mdi-alert-circle'};
  }
  return {label: t('status.converted'), color: 'green', icon: 'mdi-check-circle'};
});
</script>
