<template>
  <MainContainer :title="$t('admin.llm.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <template v-slot:meta>
      <div style="max-width: 300px">
        <p class="text-h6 mb-4">{{ $t('admin.llm.page.count', modelCount) }}</p>

        <p class="text-medium-emphasis">{{ $t('admin.llm.page.providerIntro') }}</p>
        <p class="mt-2 text-medium-emphasis">{{ $t('admin.llm.page.modelsIntro') }}</p>
        <i18n-t scope="global" keypath="admin.llm.page.defaultIntro" tag="p" class="mt-2 text-medium-emphasis">
          <template v-slot:icon><v-icon size="small" color="amber-darken-2">mdi-star</v-icon></template>
        </i18n-t>

        <v-btn @click="showCreateProviderDialog" class="mt-6" color="primary" prepend-icon="mdi-plus"
               :text="$t('admin.llm.newProvider')" block />
      </div>
    </template>

    <v-progress-linear v-if="fetching && providers.length === 0" indeterminate color="primary" />

    <EmptyState v-else-if="providers.length === 0" icon="mdi-robot" :title="$t('admin.llm.page.emptyTitle')"
                :action-text="$t('admin.llm.newProvider')" @action="showCreateProviderDialog">
      {{ $t('admin.llm.page.emptyText') }}
    </EmptyState>

    <template v-else>
      <v-alert v-if="modelCount === 0" type="info" variant="tonal" class="mb-6">
        {{ $t('admin.llm.page.noModels') }}
      </v-alert>
      <v-alert v-else-if="!hasDefault" type="warning" variant="tonal" class="mb-6">
        <i18n-t scope="global" keypath="admin.llm.page.noDefault" tag="span">
          <template v-slot:icon><v-icon size="small">mdi-star-outline</v-icon></template>
        </i18n-t>
      </v-alert>

      <v-card v-for="provider in providers" :key="provider.id" class="mb-6">
        <v-card-item>
          <v-card-title>{{ provider.name }}</v-card-title>
          <v-card-subtitle>{{ provider.base_url }}</v-card-subtitle>

          <template v-slot:append>
            <v-btn @click="showUpdateProviderDialog(provider)" icon="mdi-pencil" variant="text"
                   v-tooltip="$t('admin.llm.page.editProvider')" />
            <v-btn @click="showDeleteProviderDialog(provider)" icon="mdi-delete" variant="text"
                   v-tooltip="$t('admin.llm.page.deleteProvider')" />
          </template>
        </v-card-item>

        <v-card-text>
          <v-table v-if="provider.models.length !== 0" density="comfortable">
            <thead>
            <tr>
              <th>{{ $t('common.default') }}</th>
              <th style="width: 100%">{{ $t('common.name') }}</th>
              <th style="white-space: nowrap">{{ $t('admin.llm.pricePerMillion') }}</th>
              <th class="text-right">{{ $t('common.actions') }}</th>
            </tr>
            </thead>
            <tbody>
            <tr v-for="model in provider.models" :key="model.id">
              <td>
                <v-icon v-if="model.is_default" color="amber-darken-2" class="ml-2"
                        v-tooltip="$t('admin.llm.page.defaultModel')">
                  mdi-star
                </v-icon>
                <v-btn v-else @click="doSetDefault(model.id)" icon="mdi-star-outline" variant="text" size="small"
                       :disabled="loading" v-tooltip="$t('admin.llm.page.makeDefault')" />
              </td>
              <td>
                <template v-if="model.display_name !== null">{{ model.display_name }} (<code>{{ model.api_name }}</code>)</template>
                <code v-else>{{ model.api_name }}</code>
              </td>
              <td style="white-space: nowrap">
                <span v-if="provider.currency && model.input_price !== null && model.output_price !== null" v-tooltip="formatCachePrices(provider, model)">
                  {{ $t('admin.llm.page.price', {
                    input: formatPrice(model.input_price, provider.currency),
                    output: formatPrice(model.output_price, provider.currency),
                  }) }}
                </span>
                <span v-else class="text-medium-emphasis">{{ $t('admin.llm.page.notSet') }}</span>
              </td>
              <td class="text-right" style="white-space: nowrap">
                <v-btn @click="showUpdateModelDialog(provider, model)" icon="mdi-pencil" variant="text"
                       size="small" v-tooltip="$t('admin.llm.page.editModel')" />
                <v-btn @click="showDeleteModelDialog(model)" icon="mdi-delete" variant="text" size="small"
                       v-tooltip="$t('admin.llm.page.deleteModel')" />
              </td>
            </tr>
            </tbody>
          </v-table>
          <p v-else class="text-medium-emphasis">{{ $t('admin.llm.page.noModelsYet') }}</p>
        </v-card-text>

        <v-card-actions>
          <v-btn @click="showRemoteModelsDialog(provider)" prepend-icon="mdi-cloud-download"
                 :text="$t('admin.llm.page.fetchModels')" />
          <v-btn @click="showCreateModelDialog(provider)" prepend-icon="mdi-plus" :text="$t('admin.llm.page.addModel')" />
        </v-card-actions>
      </v-card>
    </template>

    <ProviderDialog ref="provider-dialog" v-model="dialogProvider" :loading="loading" @submit="doSaveProvider" />
    <ModelDialog ref="model-dialog" v-model="dialogModel" :loading="loading"
                 :provider-name="selectedProvider?.name ?? ''" :currency="selectedProvider?.currency ?? null"
                 :becomes-default="!hasDefault"
                 @submit="doSaveModel" />
    <RemoteModelsDialog ref="remote-models-dialog" v-model="dialogRemoteModels" :loading="loading"
                        :provider="selectedProvider" :becomes-default="!hasDefault"
                        @submit="doAddRemoteModels" @manual="showManualModelDialog" />

    <GenericDeleteDialog :title="$t('admin.llm.page.deleteProviderTitle')" v-model="dialogDeleteProvider"
                         :loading="loading" :verify="selectedProvider?.name" @delete="doDeleteProvider">
      <i18n-t scope="global" keypath="admin.llm.page.deleteProviderText" tag="span" :plural="selectedProvider?.models.length ?? 0">
        <template v-slot:name><b>{{ selectedProvider?.name }}</b></template>
      </i18n-t>
      <template v-if="selectedProvider?.models.some(m => m.is_default)">
        <br><br>
        {{ $t('admin.llm.page.deleteProviderHasDefault') }}
      </template>
    </GenericDeleteDialog>

    <GenericDeleteDialog :title="$t('admin.llm.page.deleteModelTitle')" v-model="dialogDeleteModel" :loading="loading"
                         @delete="doDeleteModel">
      <i18n-t scope="global" keypath="admin.llm.page.deleteModelText" tag="span">
        <template v-slot:name><b>{{ selectedModel?.display_name ?? selectedModel?.api_name }}</b></template>
      </i18n-t>
      <template v-if="selectedModel?.is_default">
        <br><br>
        {{ $t('admin.llm.page.deleteModelIsDefault') }}
      </template>
      <br><br>
      {{ $t('admin.llm.page.continue') }}
    </GenericDeleteDialog>
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, onMounted, ref, useTemplateRef} from "vue";
import type {LlmModelDto, LlmProviderDto, RemoteModelDto} from "~/utils/model";
import {charCount, formatPrice, showSnackbar} from "~/utils/utils";
import {
  createLlmModel,
  createLlmProvider,
  deleteLlmModel,
  deleteLlmProvider,
  errorMessage,
  getLlmProviders,
  type LlmModelPayload,
  setDefaultModel,
  type UpdateLlmProviderPayload,
  updateLlmModel,
  updateLlmProvider,
} from "~/utils/api";
import MainContainer from "~/components/MainContainer.vue";
import EmptyState from "~/components/EmptyState.vue";
import GenericDeleteDialog from "~/components/dialogs/GenericDeleteDialog.vue";
import ProviderDialog from "~/components/admin-llm/ProviderDialog.vue";
import ModelDialog from "~/components/admin-llm/ModelDialog.vue";
import RemoteModelsDialog from "~/components/admin-llm/RemoteModelsDialog.vue";
import {useI18n} from "#i18n";

/** Mirrors the API's limit on display names. */
const MAX_DISPLAY_NAME_LENGTH = 100;

const {t} = useI18n();

const providerDialog = useTemplateRef<InstanceType<typeof ProviderDialog>>('provider-dialog');
const modelDialog = useTemplateRef<InstanceType<typeof ModelDialog>>('model-dialog');
const remoteModelsDialog = useTemplateRef<InstanceType<typeof RemoteModelsDialog>>('remote-models-dialog');

const fetching = ref(true);
const loading = ref(false);
const providers = ref<LlmProviderDto[]>([]);
const selectedProvider = ref<LlmProviderDto | null>(null);
const selectedModel = ref<LlmModelDto | null>(null);

const dialogProvider = ref(false);
const dialogModel = ref(false);
const dialogRemoteModels = ref(false);
const dialogDeleteProvider = ref(false);
const dialogDeleteModel = ref(false);

const modelCount = computed(() => providers.value.reduce((sum, p) => sum + p.models.length, 0));
const hasDefault = computed(() => providers.value.some(p => p.models.some(m => m.is_default)));

const formatCachePrices = (provider: LlmProviderDto, model: LlmModelDto): string => {
  const price = (value: string | null) => formatPrice(value ?? model.input_price!, provider.currency!);
  return t('admin.llm.page.cachePrices', {read: price(model.cache_read_price), write: price(model.cache_write_price)});
};

const fetchData = async () => {
  try {
    fetching.value = true;
    providers.value = await getLlmProviders();
  } catch (e) {
    showSnackbar(t('admin.llm.page.loadFailed', {error: errorMessage(e)}));
  } finally {
    fetching.value = false;
  }
}

const showCreateProviderDialog = () => {
  selectedProvider.value = null;
  providerDialog.value!.reset();
  dialogProvider.value = true;
}

const showUpdateProviderDialog = (provider: LlmProviderDto) => {
  selectedProvider.value = provider;
  providerDialog.value!.load(provider);
  dialogProvider.value = true;
}

const showDeleteProviderDialog = (provider: LlmProviderDto) => {
  selectedProvider.value = provider;
  dialogDeleteProvider.value = true;
}

const showCreateModelDialog = (provider: LlmProviderDto) => {
  selectedProvider.value = provider;
  selectedModel.value = null;
  modelDialog.value!.reset();
  dialogModel.value = true;
}

const showRemoteModelsDialog = (provider: LlmProviderDto, closeIfNone = false) => {
  selectedProvider.value = provider;
  remoteModelsDialog.value!.load(provider, closeIfNone);
  dialogRemoteModels.value = true;
}

/** From the dialog of the fetched models, if the server does not list them. */
const showManualModelDialog = () => {
  dialogRemoteModels.value = false;
  showCreateModelDialog(selectedProvider.value!);
}

const showUpdateModelDialog = (provider: LlmProviderDto, model: LlmModelDto) => {
  selectedProvider.value = provider;
  selectedModel.value = model;
  modelDialog.value!.load(model);
  dialogModel.value = true;
}

const showDeleteModelDialog = (model: LlmModelDto) => {
  selectedModel.value = model;
  dialogDeleteModel.value = true;
}

const doSaveProvider = async (payload: UpdateLlmProviderPayload) => {
  loading.value = true;
  try {
    if (selectedProvider.value) {
      await updateLlmProvider(selectedProvider.value.id, payload);
      showSnackbar(t('admin.llm.page.providerUpdated'));
    } else {
      const provider = await createLlmProvider({
        name: payload.name,
        api_format: payload.api_format,
        base_url: payload.base_url,
        api_key: payload.api_key.action === 'SET' ? payload.api_key.value : null,
        currency: payload.currency,
      });
      showSnackbar(t('admin.llm.page.providerCreated'));
      // Only offers the models if the server lists them
      showRemoteModelsDialog(provider, true);
    }
    dialogProvider.value = false;
    await fetchData();
  } catch (e) {
    const key = selectedProvider.value ? 'admin.llm.page.saveProviderFailed' : 'admin.llm.page.createProviderFailed';
    showSnackbar(t(key, {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

const doDeleteProvider = async () => {
  loading.value = true;
  try {
    await deleteLlmProvider(selectedProvider.value!.id);
    dialogDeleteProvider.value = false;
    showSnackbar(t('admin.llm.page.providerDeleted'));
    await fetchData();
  } catch (e) {
    showSnackbar(t('admin.llm.page.deleteProviderFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

const doSaveModel = async (payload: LlmModelPayload) => {
  loading.value = true;
  try {
    if (selectedModel.value) {
      await updateLlmModel(selectedModel.value.id, payload);
      showSnackbar(t('admin.llm.page.modelUpdated'));
    } else {
      await createLlmModel(selectedProvider.value!.id, payload);
      showSnackbar(t('admin.llm.page.modelsAdded', 1));
    }
    dialogModel.value = false;
    await fetchData();
  } catch (e) {
    const key = selectedModel.value ? 'admin.llm.page.saveModelFailed' : 'admin.llm.page.addModelFailed';
    showSnackbar(t(key, {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

/** Adds the models one by one, so the first becomes the default if there is none. */
const doAddRemoteModels = async (models: RemoteModelDto[]) => {
  const providerId = selectedProvider.value!.id;
  const added: string[] = [];
  const failed: string[] = [];
  loading.value = true;
  try {
    for (const model of models) {
      const displayName = model.display_name?.trim() ?? '';
      try {
        await createLlmModel(providerId, {
          api_name: model.api_name,
          // Shows the API name instead of a name the API would reject
          display_name: charCount(displayName) <= MAX_DISPLAY_NAME_LENGTH ? displayName || null : null,
          max_output_tokens: null,
          input_price: null,
          output_price: null,
          cache_read_price: null,
          cache_write_price: null,
        });
        added.push(model.api_name);
      } catch (e) {
        failed.push(`${model.display_name ?? model.api_name}: ${errorMessage(e)}`);
      }
    }
    await fetchData();
    // The dialog marks the models of the refreshed provider as added
    selectedProvider.value = providers.value.find(p => p.id === providerId) ?? null;
  } finally {
    loading.value = false;
  }

  if (failed.length === 0) {
    dialogRemoteModels.value = false;
    showSnackbar(t('admin.llm.page.modelsAdded', added.length));
  } else {
    remoteModelsDialog.value?.unselect(added);
    const params = {added: added.length, total: models.length, error: failed[0], more: failed.length - 1};
    showSnackbar(failed.length > 1 ? t('admin.llm.page.partlyAddedMore', params) : t('admin.llm.page.partlyAdded', params));
  }
}

const doDeleteModel = async () => {
  loading.value = true;
  try {
    await deleteLlmModel(selectedModel.value!.id);
    dialogDeleteModel.value = false;
    showSnackbar(t('admin.llm.page.modelDeleted'));
    await fetchData();
  } catch (e) {
    showSnackbar(t('admin.llm.page.deleteModelFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

const doSetDefault = async (modelId: string) => {
  loading.value = true;
  try {
    await setDefaultModel(modelId);
    showSnackbar(t('admin.llm.page.defaultChanged'));
  } catch (e) {
    showSnackbar(t('admin.llm.page.setDefaultFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
    // Also after errors, e.g. UNKNOWN_MODEL when another admin deleted the model.
    await fetchData();
  }
}

onMounted(async () => {
  await fetchData();
});
</script>
