<template>
  <v-menu>
    <template v-slot:activator="{ props: activator }">
      <v-btn v-bind="activator" :icon="filter === DocumentFilter.ALL ? 'mdi-filter-outline' : 'mdi-filter'"
             :color="filter === DocumentFilter.ALL ? undefined : 'primary'"
             variant="text" size="small" density="comfortable" class="ml-1" v-tooltip="$t('documents.statusFilter.filterByStatus')"/>
    </template>

    <v-list density="compact" color="primary">
      <v-list-item v-for="option in options" :key="option.value" :title="option.label"
                   :active="filter === option.value" @click="filter = option.value">
        <template v-slot:append>
          <span class="ml-4 text-medium-emphasis">{{ option.count }}</span>
        </template>
      </v-list-item>
    </v-list>
  </v-menu>
</template>

<script setup lang="ts">
import {computed} from "vue";
import {DocumentFilter} from "~/utils/model";
import {useI18n} from "#i18n";

const props = defineProps<{
  modelValue: DocumentFilter,
  counts: { all: number, converted: number, failed: number, pending: number },
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: DocumentFilter): void
}>();

const {t} = useI18n();

const filter = computed({
  get: () => props.modelValue,
  set: (val: DocumentFilter) => emit('update:modelValue', val)
});

const options = computed(() => [
  {value: DocumentFilter.ALL, label: t('documents.statusFilter.all'), count: props.counts.all},
  {value: DocumentFilter.CONVERTED, label: t('status.converted'), count: props.counts.converted},
  {value: DocumentFilter.FAILED, label: t('status.failed'), count: props.counts.failed},
  {value: DocumentFilter.PENDING, label: t('status.pending'), count: props.counts.pending},
]);
</script>
