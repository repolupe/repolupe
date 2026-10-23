<template>
  <MainContainer :title="$t('settings.preferences.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <v-card v-if="user">
      <v-table>
        <tbody>
        <tr>
          <td>{{ $t('common.model') }}</td>
          <td>
            <v-progress-circular v-if="fetchingModels" indeterminate size="16" width="2"/>
            <span v-else>{{ modelLabel }}</span>
          </td>
          <td><v-btn @click="showModelDialog" icon="mdi-pencil" variant="text" :disabled="fetchingModels"/></td>
        </tr>
        <tr>
          <td>{{ $t('settings.preferences.language') }}</td>
          <td>{{ user.locale ?? $t('settings.preferences.browserDefault', {locale: browserLocale}) }}</td>
          <td><v-btn @click="showLocaleDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        <tr v-if="user.can_manage_repositories">
          <td>
            {{ $t('settings.preferences.page.autoCommit') }}
            <div class="text-caption text-medium-emphasis">{{ $t('settings.preferences.page.autoCommitHint') }}</div>
          </td>
          <td>
            <v-switch :model-value="user.auto_commit" @update:model-value="updateAutoCommit(!!$event)"
                      :loading="updatingAutoCommit" :disabled="updatingAutoCommit"
                      color="primary" density="compact" hide-details/>
          </td>
          <td/>
        </tr>
        </tbody>
      </v-table>
    </v-card>

    <ModelDialog ref="model-dialog" v-model="dialogModel" :loading="loading" :models="models" @submit="updateModel"/>
    <LocaleDialog ref="locale-dialog" v-model="dialogLocale" :loading="loading" @submit="updateLocale"/>
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, onMounted, ref, useTemplateRef} from "vue";
import {refreshUser, useUser} from "~/composables/states";
import {ApiError, errorMessage, getModels, setMyAutoCommit, setMyDefaultModel, setMyLocale} from "~/utils/api";
import {ErrorCode, type ModelDto} from "~/utils/model";
import {showSnackbar} from "~/utils/utils";
import {useI18n} from "#i18n";
import MainContainer from "~/components/MainContainer.vue";
import ModelDialog from "~/components/settings/ModelDialog.vue";
import LocaleDialog from "~/components/settings/LocaleDialog.vue";

const modelDialog = useTemplateRef<InstanceType<typeof ModelDialog>>('model-dialog');
const localeDialog = useTemplateRef<InstanceType<typeof LocaleDialog>>('locale-dialog');

const {t} = useI18n();
const user = useUser();
const browserLocale = navigator.language;

const models = ref<ModelDto[]>([]);
const fetchingModels = ref(false);
const loading = ref(false);
const dialogModel = ref(false);
const dialogLocale = ref(false);
const updatingAutoCommit = ref(false);

const modelLabel = computed(() => {
  if (models.value.length === 0) {
    return t('settings.preferences.page.noModels');
  }
  const chosen = models.value.find(m => m.id === user.value?.default_model_id);
  if (chosen) {
    return `${chosen.display_name} (${chosen.provider_name})`;
  }
  const defaultModel = models.value.find(m => m.is_default);
  return defaultModel
    ? t('settings.preferences.defaultModel', {name: defaultModel.display_name})
    : t('settings.preferences.defaultNone');
});

const fetchModels = async () => {
  fetchingModels.value = true;
  try {
    models.value = await getModels();
  } catch (e) {
    showSnackbar(t('settings.preferences.page.modelsLoadFailed', {error: errorMessage(e)}));
  } finally {
    fetchingModels.value = false;
  }
}

const showModelDialog = () => {
  if (models.value.length === 0) {
    showSnackbar(t('settings.preferences.page.noModelsAskAdmin'));
    return;
  }
  modelDialog.value!.load(user.value!.default_model_id);
  dialogModel.value = true;
}

const updateModel = async (modelId: string | null) => {
  loading.value = true;
  try {
    await setMyDefaultModel(modelId);
    dialogModel.value = false;
    await refreshUser();
    showSnackbar(t('settings.preferences.page.modelUpdated'));
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_MODEL) {
      // deleted in the meantime
      await fetchModels();
    }
    showSnackbar(t('settings.preferences.page.modelSaveFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

const showLocaleDialog = () => {
  localeDialog.value!.load(user.value!.locale);
  dialogLocale.value = true;
}

const updateLocale = async (locale: string | null) => {
  loading.value = true;
  try {
    await setMyLocale(locale);
    dialogLocale.value = false;
    await refreshUser();
    showSnackbar(t('settings.preferences.page.languageUpdated'));
  } catch (e) {
    showSnackbar(t('settings.preferences.page.languageSaveFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

const updateAutoCommit = async (autoCommit: boolean) => {
  updatingAutoCommit.value = true;
  try {
    await setMyAutoCommit(autoCommit);
    await refreshUser();
    showSnackbar(t(autoCommit ? 'settings.preferences.page.autoCommitOn' : 'settings.preferences.page.autoCommitOff'));
  } catch (e) {
    showSnackbar(t('settings.preferences.page.autoCommitSaveFailed', {error: errorMessage(e)}));
  } finally {
    updatingAutoCommit.value = false;
  }
}

onMounted(fetchModels);
</script>
