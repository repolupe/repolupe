<template>
  <v-select v-model="selection" :items="items" item-title="name" item-value="id" prepend-inner-icon="mdi-folder"
            density="compact" multiple :disabled="props.disabled"
            variant="plain" menu-icon="" hide-details class="plain-select flex-grow-0" style="max-width: 280px">
    <template v-slot:selection="{ index }">
      <span v-if="index === 0" class="text-truncate">{{ summary }}</span>
    </template>
  </v-select>
</template>

<script setup lang="ts">
import {computed} from "vue";
import type {RepositoryDto, RepositoryScope} from "~/utils/model";
import {allRepositoriesTitle, repositoryScopeSummary} from "~/utils/utils";

/** Stands for `all_repositories` in the select. */
const ALL_REPOSITORIES = '__all__';
/**
 * Stands for an empty selection. It is no item, so it shows no checkbox, but the select renders it like a selection,
 * so the summary ("No repository") is laid out like any other.
 */
const NO_REPOSITORY = '__none__';

const props = defineProps<{
  modelValue: RepositoryScope,
  repositories: RepositoryDto[],
  disabled?: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: RepositoryScope): void,
}>();

const items = computed(() => [
  {name: allRepositoriesTitle(), id: ALL_REPOSITORIES},
  {type: 'divider'},
  ...props.repositories,
]);

const selection = computed({
  get: () => {
    if (props.modelValue.all_repositories) {
      return [ALL_REPOSITORIES];
    }
    const ids = props.modelValue.repository_ids;
    return ids.length > 0 ? ids : [NO_REPOSITORY];
  },
  set: (val: string[]) => {
    const ids = val.filter(id => id !== ALL_REPOSITORIES && id !== NO_REPOSITORY);
    const pickedAll = val.includes(ALL_REPOSITORIES) && !props.modelValue.all_repositories;
    // picking "all" clears the single repositories, deselecting everything selects no repository
    emit('update:modelValue', pickedAll
        ? {all_repositories: true, repository_ids: []}
        : {all_repositories: false, repository_ids: ids});
  },
});

const summary = computed(() => repositoryScopeSummary(props.modelValue, props.repositories));
</script>

<style scoped>
/* the plain variant leaves room for a label above the value; there is no label here, so center icon and value */
.plain-select :deep(.v-field__prepend-inner),
.plain-select :deep(.v-field__input) {
  align-items: center;
  padding-top: 0;
  padding-bottom: 0;
}
</style>
