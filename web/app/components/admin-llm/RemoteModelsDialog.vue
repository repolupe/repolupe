<template>
  <v-dialog v-model="dialog" width="auto">
    <v-card width="600" :title="$t('admin.llm.remoteModelsDialog.title', {name: props.provider?.name ?? ''})">
      <template v-slot:text>
        <div v-if="fetching" class="py-6 text-center text-medium-emphasis">
          <v-progress-circular indeterminate color="primary" class="mb-4" />
          <p>{{ $t('admin.llm.remoteModelsDialog.fetching') }}</p>
        </div>

        <template v-else-if="error !== null">
          <v-alert type="error" variant="tonal">{{ error }}</v-alert>
          <p class="mt-4 text-medium-emphasis">{{ $t('admin.llm.remoteModelsDialog.addByNameHint') }}</p>
        </template>

        <p v-else-if="models.length === 0" class="text-medium-emphasis">{{ $t('admin.llm.remoteModelsDialog.noModels') }}</p>

        <template v-else>
          <p class="text-medium-emphasis mb-4">
            {{ $t('admin.llm.remoteModelsDialog.intro') }}
          </p>

          <SearchField v-model="query" class="mb-2" />

          <v-checkbox v-if="selectable.length !== 0" :model-value="allSelected" :indeterminate="someSelected"
                      @update:model-value="toggleAll" :disabled="props.loading" hide-details density="compact"
                      :label="query.trim() ? $t('admin.llm.remoteModelsDialog.selectAllMatches', {count: selectable.length}) : $t('admin.llm.remoteModelsDialog.selectAll')" />

          <v-list density="compact" max-height="400" class="border rounded">
            <v-list-item v-for="model in filtered" :key="model.api_name" :disabled="props.loading || added.has(model.api_name)"
                         @click="toggle(model.api_name)">
              <template v-slot:prepend>
                <v-checkbox-btn :model-value="added.has(model.api_name) || selected.has(model.api_name)"
                                :disabled="props.loading || added.has(model.api_name)" tabindex="-1" />
              </template>
              <v-list-item-title>{{ model.display_name ?? model.api_name }}</v-list-item-title>
              <v-list-item-subtitle v-if="model.display_name !== null">
                <code>{{ model.api_name }}</code>
              </v-list-item-subtitle>
              <template v-if="added.has(model.api_name)" v-slot:append>
                <v-chip size="small" :text="$t('common.added')" />
              </template>
            </v-list-item>
            <v-list-item v-if="filtered.length === 0" class="text-medium-emphasis">
              {{ $t('admin.llm.remoteModelsDialog.noMatch', {query: query.trim()}) }}
            </v-list-item>
          </v-list>

          <v-alert v-if="props.becomesDefault && selected.size !== 0" type="info" variant="tonal" density="compact"
                   class="mt-4">
            {{ $t('admin.llm.remoteModelsDialog.becomesDefault') }}
          </v-alert>
        </template>
      </template>

      <template v-slot:actions>
        <v-btn v-if="error !== null" :text="$t('common.retry')" prepend-icon="mdi-refresh" @click="fetchModels(false)" />
        <v-spacer />
        <v-btn :text="$t('common.cancel')" @click="dialog = false" />
        <v-btn v-if="error !== null" @click="emit('manual')" color="primary" variant="elevated"
               prepend-icon="mdi-plus" :text="$t('admin.llm.remoteModelsDialog.addByName')" />
        <v-btn v-else @click="submit" color="primary" variant="elevated" :loading="props.loading"
               :disabled="fetching || selected.size === 0" prepend-icon="mdi-plus"
               :text="$t('admin.llm.remoteModelsDialog.addModels', selected.size)" />
      </template>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {errorMessage, getRemoteLlmModels} from "~/utils/api";
import type {LlmProviderDto, RemoteModelDto} from "~/utils/model";
import SearchField from "~/components/SearchField.vue";

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  provider: LlmProviderDto | null,
  /** Whether the first model added becomes the default, i.e. there is none yet. */
  becomesDefault: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  /** The models to add, in the order they are listed. */
  (e: 'submit', value: RemoteModelDto[]): void,
  /** The server did not list its models, add one by name instead. */
  (e: 'manual'): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

/** The provider whose models are fetched, set by `load` before `props.provider` follows. */
const providerId = ref<string | null>(null);
const fetching = ref(false);
const error = ref<string | null>(null);
const models = ref<RemoteModelDto[]>([]);
const query = ref('');
const selected = ref(new Set<string>());

/** The API names the provider already has. */
const added = computed(() => new Set(props.provider?.models.map(m => m.api_name) ?? []));

const filtered = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) {
    return models.value;
  }
  return models.value.filter(m => m.api_name.toLowerCase().includes(q)
      || (m.display_name?.toLowerCase().includes(q) ?? false));
});

/** The models shown that can be selected. */
const selectable = computed(() => filtered.value.filter(m => !added.value.has(m.api_name)));
const allSelected = computed(() => selectable.value.length !== 0
    && selectable.value.every(m => selected.value.has(m.api_name)));
const someSelected = computed(() => !allSelected.value && selectable.value.some(m => selected.value.has(m.api_name)));

const toggle = (apiName: string) => {
  const next = new Set(selected.value);
  if (!next.delete(apiName)) {
    next.add(apiName);
  }
  selected.value = next;
};

const toggleAll = () => {
  const next = new Set(selected.value);
  const select = !allSelected.value;
  for (const model of selectable.value) {
    if (select) {
      next.add(model.api_name);
    } else {
      next.delete(model.api_name);
    }
  }
  selected.value = next;
};

/** With `closeIfNone`, the dialog closes instead of showing an error or an empty list. */
const fetchModels = async (closeIfNone: boolean) => {
  const id = providerId.value;
  if (id === null) {
    return;
  }
  fetching.value = true;
  error.value = null;
  let result: RemoteModelDto[] = [];
  let failure: string | null = null;
  try {
    result = await getRemoteLlmModels(id);
  } catch (e) {
    failure = errorMessage(e);
  }
  // Ignore the result if another provider was opened meanwhile
  if (providerId.value !== id) {
    return;
  }
  if (closeIfNone && (failure !== null || result.length === 0)) {
    // Keeps showing the progress while the dialog closes
    dialog.value = false;
    return;
  }
  models.value = result;
  error.value = failure;
  fetching.value = false;
};

const submit = () => {
  // Models added meanwhile, e.g. by another admin, are skipped
  emit('submit', models.value.filter(m => selected.value.has(m.api_name) && !added.value.has(m.api_name)));
};

defineExpose({
  /**
   * Clears the dialog and fetches the models of `provider`, which is also passed as the prop.
   * With `closeIfNone`, the dialog closes if the server lists no models or the request fails.
   */
  load: async (provider: LlmProviderDto, closeIfNone = false) => {
    providerId.value = provider.id;
    models.value = [];
    query.value = '';
    selected.value = new Set();
    await fetchModels(closeIfNone);
  },
  /** Unselects the models that were added, e.g. after some of them failed. */
  unselect: (apiNames: string[]) => {
    const next = new Set(selected.value);
    apiNames.forEach(name => next.delete(name));
    selected.value = next;
  },
});
</script>
