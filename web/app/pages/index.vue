<template>
  <div class="new-page" :class="{'new-page-temporary': temporary}">
    <v-btn class="temporary-toggle fade-in" :class="{'fade-in-hidden': !showSelects}" variant="text"
           :icon="temporary ? 'mdi-close' : 'mdi-progress-clock'" :disabled="loading"
           v-tooltip="$t('chat.temporary')" @click="temporary = !temporary"/>
    <div class="new-column">
      <InstanceHero class="mb-6" :temporary="temporary"/>

      <v-alert v-if="loadFailed" type="error" variant="tonal" class="mb-6">
        {{ $t('chat.startPage.loadFailed') }}
        <template v-slot:append>
          <v-btn variant="text" :text="$t('common.retry')" @click="load"/>
        </template>
      </v-alert>

      <v-alert v-else-if="modelsLoaded && models.length === 0" type="warning" variant="tonal" class="mb-6">
        {{ $t('chat.startPage.noModel') }}
        <i18n-t scope="global" v-if="isAdmin" keypath="chat.startPage.addProvider" tag="span">
          <template v-slot:link>
            <NuxtLink to="/settings/admin/llm">{{ $t('chat.startPage.addProviderLink') }}</NuxtLink>
          </template>
        </i18n-t>
        <template v-else>{{ $t('chat.startPage.askAdmin') }}</template>
      </v-alert>

      <!-- the input is rendered while loading, so the view transition from a chat can move it here -->
      <MessageInput v-model="content" v-model:attachment="attachment" :placeholder="$t('chat.placeholder')"
                    :can-send="canSubmit" :sending="loading" :disabled="loading" @send="submit"/>

      <!-- hidden but taking its space while loading, so the (vertically centered) input does not jump -->
      <div class="fade-in mt-4 d-flex align-center flex-wrap ga-3" :class="{'fade-in-hidden': !showSelects}">
        <ChatModelSelect v-if="fetching" :model-value="null" :models="[]"/>
        <template v-else>
          <RepositoryScopeSelect v-if="repositories.length > 0" v-model="scope" :repositories="repositories" :disabled="loading"/>
          <ChatModelSelect v-if="models.length > 0" v-model="modelId" :models="models" :disabled="loading"/>
        </template>
      </div>
    </div>

    <div v-if="poweredBy" class="powered-by text-caption text-medium-emphasis">Powered by {{ PRODUCT_NAME }}</div>
  </div>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, onMounted, ref, watch} from "vue";
import {navigateTo, useRoute} from "#app";
import {useI18n} from "#i18n";
import {NuxtLink} from "#components";
import {ApiError, createChat, errorMessage, getModels, getRepositories} from "~/utils/api";
import {ErrorCode, type ModelDto, type RepositoryDto, type RepositoryScope, UserRole} from "~/utils/model";
import {showSnackbar, type PendingAttachment} from "~/utils/utils";
import {PRODUCT_NAME, refreshChats, useInstanceName, useUser} from "~/composables/states";
import MessageInput from "~/components/chat/MessageInput.vue";
import RepositoryScopeSelect from "~/components/chat/RepositoryScopeSelect.vue";
import ChatModelSelect from "~/components/chat/ChatModelSelect.vue";
import InstanceHero from "~/components/chat/InstanceHero.vue";

const {t} = useI18n();
const route = useRoute();
const user = useUser();

/** The selects fade in after the view transition from a chat moved the input here (see MessageInput). */
const SELECTS_DELAY_MS = 350;

const fetching = ref(true);
const selectsDelayPassed = ref(false);
const loading = ref(false);
const loadFailed = ref(false);
const modelsLoaded = ref(false);
const repositories = ref<RepositoryDto[]>([]);
const models = ref<ModelDto[]>([]);
const content = ref('');
/** Sent with the first message once uploaded. */
const attachment = ref<PendingAttachment | null>(null);
const scope = ref<RepositoryScope>({all_repositories: true, repository_ids: []});
/** Chosen for this chat, `null` uses the user's model. */
const modelId = ref<string | null>(null);
/** Not listed in the history, and deleted a day after its last message. */
const temporary = ref(false);
const instanceName = useInstanceName();

const poweredBy = computed(() => instanceName.value !== null && instanceName.value !== PRODUCT_NAME);

const showSelects = computed(() => !fetching.value && selectsDelayPassed.value);

const isAdmin = computed(() => user.value?.role === UserRole.ADMIN);

const canSubmit = computed(() => !fetching.value && !loadFailed.value
    && (attachment.value ? !!attachment.value.uploaded : content.value.trim().length > 0));

/** `?repository=<id>` preselects that repository (linked from the repository page). */
const applyRepositoryQuery = () => {
  const id = route.query.repository;
  if (repositories.value.length === 0) {
    // without repositories, "all" would be misleading
    scope.value = {all_repositories: false, repository_ids: []};
  } else if (typeof id === 'string' && repositories.value.some(r => r.id === id)) {
    scope.value = {all_repositories: false, repository_ids: [id]};
  } else {
    scope.value = {all_repositories: true, repository_ids: []};
  }
};

const submit = async () => {
  if (loading.value || fetching.value || loadFailed.value) {
    return;
  }
  if (attachment.value && !attachment.value.uploaded) {
    showSnackbar(t('chat.startPage.waitForUpload'));
    return;
  }
  if (!content.value.trim() && !attachment.value) {
    showSnackbar(t('chat.startPage.enterQuestion'));
    return;
  }

  loading.value = true;
  try {
    const created = await createChat({
      content: content.value.trim(),
      attachment_id: attachment.value?.uploaded?.id ?? null,
      all_repositories: scope.value.all_repositories,
      repository_ids: scope.value.all_repositories ? [] : scope.value.repository_ids,
      title: null,
      model_id: modelId.value,
      temporary: temporary.value,
    });
    await refreshChats();
    // lets the chat page show the temporary background before the chat is loaded
    await navigateTo({path: '/chat/' + created.id, state: {temporary: created.temporary}});
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.NO_MODEL_CONFIGURED) {
      showSnackbar(t('chat.noModelConfigured'));
    } else if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_REPOSITORY) {
      showSnackbar(t('chat.startPage.unknownRepository'));
      await fetchRepositories();
    } else if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_MODEL) {
      showSnackbar(t('chat.unknownModel'));
      modelId.value = null;
      await fetchModels();
    } else if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_ATTACHMENT) {
      showSnackbar(t('chat.unknownAttachment'));
      attachment.value = null;
    } else if (e instanceof ApiError && e.code === ErrorCode.RATE_LIMITED) {
      showSnackbar(t('chat.rateLimited'));
    } else {
      showSnackbar(t('chat.page.sendFailed', {error: errorMessage(e)}));
    }
  } finally {
    loading.value = false;
  }
};

const fetchRepositories = async () => {
  try {
    repositories.value = await getRepositories();
    const ids = new Set(repositories.value.map(r => r.id));
    scope.value = {...scope.value, repository_ids: scope.value.repository_ids.filter(id => ids.has(id))};
  } catch (e) {
    showSnackbar(t('repositories.listPage.loadFailed', {error: errorMessage(e)}));
  }
};

const fetchModels = async () => {
  try {
    models.value = await getModels();
  } catch (e) {
    showSnackbar(t('settings.preferences.page.modelsLoadFailed', {error: errorMessage(e)}));
  }
};

watch(() => route.query.repository, () => applyRepositoryQuery());

const load = async () => {
  fetching.value = true;
  loadFailed.value = false;
  const [repositoriesResult, modelsResult] = await Promise.allSettled([getRepositories(), getModels()]);
  if (repositoriesResult.status === 'fulfilled') {
    repositories.value = repositoriesResult.value;
  } else {
    loadFailed.value = true;
    showSnackbar(t('repositories.listPage.loadFailed', {error: errorMessage(repositoriesResult.reason)}));
  }
  if (modelsResult.status === 'fulfilled') {
    models.value = modelsResult.value;
    modelsLoaded.value = true;
  }
  applyRepositoryQuery();
  fetching.value = false;
};

const timeouts: ReturnType<typeof setTimeout>[] = [];

onMounted(() => {
  timeouts.push(setTimeout(() => selectsDelayPassed.value = true, SELECTS_DELAY_MS));
  load();
});

onBeforeUnmount(() => timeouts.forEach(clearTimeout));
</script>

<style scoped>
.new-page {
  position: relative;
  display: flex;
  align-items: center;
  min-height: calc(100dvh - var(--v-layout-top, 0px) - var(--v-layout-bottom, 0px));
  padding: 30px 0;
  transition: background-color 250ms;
}

.new-page-temporary {
  background-color: rgb(var(--v-theme-temporary));
}

.fade-in {
  transition: opacity 200ms, visibility 200ms;
}

.fade-in-hidden {
  opacity: 0;
  visibility: hidden;
}

.temporary-toggle {
  position: absolute;
  top: 8px;
  right: 8px;
}

.powered-by {
  position: absolute;
  right: 16px;
  bottom: 8px;
}

.new-column {
  width: 100%;
  max-width: 800px;
  margin: 0 auto;
  padding: 0 16px;
}
</style>
