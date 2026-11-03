<template>
  <ScopeSelect :model-value="scope" :items="items" :header="$t('repositories.title')"
               :all-title="$t('chat.allRepositories')" icon="mdi-folder-outline" none-icon="mdi-folder-remove-outline"
               :summary="repositoryScopeSummary(props.modelValue, props.repositories)" :variant="props.variant"
               :disabled="props.disabled"
               @update:model-value="emit('update:modelValue', {all_repositories: $event.all, repository_ids: $event.ids})"/>
</template>

<script setup lang="ts">
import {computed} from "vue";
import type {RepositoryDto, RepositoryScope} from "~/utils/model";
import {repositoryScopeSummary} from "~/utils/utils";
import ScopeSelect, {type Scope, type ScopeItem} from "~/components/chat/ScopeSelect.vue";

const props = defineProps<{
  modelValue: RepositoryScope,
  repositories: RepositoryDto[],
  /** See `ScopeSelect`. */
  variant: 'item' | 'chip',
  disabled?: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: RepositoryScope): void,
}>();

const scope = computed<Scope>(() => ({all: props.modelValue.all_repositories, ids: props.modelValue.repository_ids}));

const items = computed<ScopeItem[]>(() => props.repositories.map(r => ({id: r.id, title: r.name})));
</script>
