<template>
  <v-tooltip :text="props.repository.last_error ?? ''" :disabled="!props.repository.last_error" location="top">
    <template v-slot:activator="{ props: tooltip }">
      <v-chip v-bind="tooltip" :color="info.color" :prepend-icon="info.icon" size="small" label>
        {{ info.label }}
      </v-chip>
    </template>
  </v-tooltip>
</template>

<script setup lang="ts">
import {computed} from "vue";
import {useI18n} from "#i18n";
import {type RepositoryDto, RepositorySyncStatus} from "~/utils/model";

const props = defineProps<{
  repository: RepositoryDto,
}>();

const {t} = useI18n();

const info = computed(() => {
  switch (props.repository.sync_status) {
    case RepositorySyncStatus.PENDING:
      return {label: t('status.pending'), color: 'grey', icon: 'mdi-clock-outline'};
    case RepositorySyncStatus.SYNCING:
      return {label: t('status.syncing'), color: 'blue', icon: 'mdi-sync'};
    case RepositorySyncStatus.READY:
      return {label: t('status.ready'), color: 'green', icon: 'mdi-check-circle'};
    case RepositorySyncStatus.FAILED:
      return {label: t('status.failed'), color: 'red', icon: 'mdi-alert-circle'};
  }
});
</script>
