<template>
  <v-dialog v-model="dialog" max-width="560">
    <v-card :title="$t('repositories.newRepository')">
      <template v-slot:text>
        <v-row dense>
          <v-col v-for="kind in kinds" :key="kind.value" cols="12" sm="6">
            <v-card variant="outlined" class="kind-card h-100" @click="emit('select', kind.value)">
              <v-card-text class="text-center pa-6">
                <v-icon size="48" color="primary" class="mb-3">{{ kind.icon }}</v-icon>
                <p class="text-h6 mb-2">{{ kind.title }}</p>
                <p class="text-medium-emphasis">{{ kind.description }}</p>
              </v-card-text>
            </v-card>
          </v-col>
        </v-row>
      </template>

      <template v-slot:actions>
        <v-btn :text="$t('common.cancel')" @click="dialog = false"/>
      </template>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed} from "vue";
import {useI18n} from "#i18n";

/** Whether the repository is synced from a remote or only exists on the server. */
export type RepositoryKind = 'REMOTE' | 'LOCAL';

const props = defineProps<{
  modelValue: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'select', kind: RepositoryKind): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const {t} = useI18n();

const kinds = computed((): { value: RepositoryKind, icon: string, title: string, description: string }[] => [
  {
    value: 'REMOTE',
    icon: 'mdi-cloud-sync-outline',
    title: t('repositories.remote'),
    description: t('repositories.kindDialog.remoteDescription'),
  },
  {
    value: 'LOCAL',
    icon: 'mdi-server',
    title: t('repositories.local'),
    description: t('repositories.kindDialog.localDescription'),
  },
]);
</script>

<style scoped>
.kind-card {
  border-color: rgba(var(--v-border-color), 0.25);
}
</style>
