<template>
  <div class="new-page" :class="{'new-page-temporary': temporary}">
    <v-btn class="temporary-toggle" variant="text"
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
                    :can-send="canSubmit" :sending="loading" :disabled="loading" @send="submit">
        <!-- assumed while loading, so the attach button does not turn into the menu's button -->
        <template v-if="fetching || repositories.length > 0 || mcpServers.length > 0" v-slot:menu>
          <RepositoryScopeSelect v-if="repositories.length > 0" v-model="repositoryScope" :repositories="repositories"
                                 variant="item" :disabled="loading"/>
          <McpServerScopeSelect v-if="mcpServers.length > 0" v-model="mcpServerScope" :servers="mcpServers"
                                variant="item" :disabled="loading"/>
        </template>
        <!-- only the scopes that are not "all" -->
        <template v-slot:start>
          <RepositoryScopeSelect v-if="repositories.length > 0" v-model="repositoryScope" :repositories="repositories"
                                 variant="chip" :disabled="loading"/>
          <McpServerScopeSelect v-if="mcpServers.length > 0" v-model="mcpServerScope" :servers="mcpServers"
                                variant="chip" :disabled="loading"/>
        </template>
        <template v-slot:end>
          <ChatModelSelect v-if="models.length > 0" v-model="modelId" :models="models" :disabled="loading"/>
        </template>
      </MessageInput>
    </div>

    <div v-if="poweredBy" class="powered-by text-caption text-medium-emphasis">Powered by {{ PRODUCT_NAME }}</div>
  </div>
</template>

<script setup lang="ts">
import {computed, onMounted, ref, watch} from "vue";
import {navigateTo, useRoute} from "#app";
import {useI18n} from "#i18n";
import {NuxtLink} from "#components";
import {ApiError, createChat, errorMessage, getMcpServers, getModels, getRepositories} from "~/utils/api";
import {
  ErrorCode,
  type McpServerDto,
  type McpServerScope,
  type ModelDto,
  type RepositoryDto,
  type RepositoryScope,
  UserRole,
} from "~/utils/model";
import {isMcpServerOn, showSnackbar, type PendingAttachment} from "~/utils/utils";
import {PRODUCT_NAME, refreshChats, useInstanceName, useUser} from "~/composables/states";
import MessageInput from "~/components/chat/MessageInput.vue";
import McpServerScopeSelect from "~/components/chat/McpServerScopeSelect.vue";
import RepositoryScopeSelect from "~/components/chat/RepositoryScopeSelect.vue";
import ChatModelSelect from "~/components/chat/ChatModelSelect.vue";
import InstanceHero from "~/components/chat/InstanceHero.vue";

const {t} = useI18n();
const route = useRoute();
const user = useUser();

const fetching = ref(true);
const loading = ref(false);
const loadFailed = ref(false);
const modelsLoaded = ref(false);
const repositories = ref<RepositoryDto[]>([]);
const models = ref<ModelDto[]>([]);
const content = ref('');
/** Sent with the first message once uploaded. */
const attachment = ref<PendingAttachment | null>(null);
const repositoryScope = ref<RepositoryScope>({all_repositories: true, repository_ids: []});
/** The MCP servers that are on, the others give no tools in any chat. */
const mcpServers = ref<McpServerDto[]>([]);
const mcpServerScope = ref<McpServerScope>({all_mcp_servers: true, mcp_server_ids: []});
/** Chosen for this chat, `null` uses the user's model. */
const modelId = ref<string | null>(null);
/** Not listed in the history, and deleted a day after its last message. */
const temporary = ref(false);
const instanceName = useInstanceName();

const poweredBy = computed(() => instanceName.value !== null && instanceName.value !== PRODUCT_NAME);

const isAdmin = computed(() => user.value?.role === UserRole.ADMIN);

const canSubmit = computed(() => !fetching.value && !loadFailed.value
    && (attachment.value ? !!attachment.value.uploaded : content.value.trim().length > 0));

/** `?repository=<id>` preselects that repository (linked from the repository page). */
const applyRepositoryQuery = () => {
  const id = route.query.repository;
  if (repositories.value.length === 0) {
    // without repositories, "all" would be misleading
    repositoryScope.value = {all_repositories: false, repository_ids: []};
  } else if (typeof id === 'string' && repositories.value.some(r => r.id === id)) {
    repositoryScope.value = {all_repositories: false, repository_ids: [id]};
  } else {
    repositoryScope.value = {all_repositories: true, repository_ids: []};
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
      all_repositories: repositoryScope.value.all_repositories,
      repository_ids: repositoryScope.value.all_repositories ? [] : repositoryScope.value.repository_ids,
      all_mcp_servers: mcpServerScope.value.all_mcp_servers,
      mcp_server_ids: mcpServerScope.value.all_mcp_servers ? [] : mcpServerScope.value.mcp_server_ids,
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
    } else if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_MCP_SERVER) {
      showSnackbar(t('chat.startPage.unknownMcpServer'));
      await fetchMcpServers();
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
    repositoryScope.value = {
      ...repositoryScope.value,
      repository_ids: repositoryScope.value.repository_ids.filter(id => ids.has(id)),
    };
  } catch (e) {
    showSnackbar(t('repositories.listPage.loadFailed', {error: errorMessage(e)}));
  }
};

/**
 * Keeps the selected servers that are still on. Without any, they are not offered and the chat gets all servers, so
 * turning one on later applies to it, like before servers could be selected.
 */
const setMcpServers = (servers: McpServerDto[]) => {
  mcpServers.value = servers.filter(isMcpServerOn);
  const ids = new Set(mcpServers.value.map(s => s.id));
  mcpServerScope.value = ids.size === 0
      ? {all_mcp_servers: true, mcp_server_ids: []}
      : {...mcpServerScope.value, mcp_server_ids: mcpServerScope.value.mcp_server_ids.filter(id => ids.has(id))};
};

/** On failure they are not offered: the servers are optional, the chat gets all of them. */
const fetchMcpServers = async () => {
  try {
    setMcpServers(await getMcpServers());
  } catch {
    setMcpServers([]);
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
  // the MCP servers are optional, `fetchMcpServers` handles a failure itself
  const [[repositoriesResult, modelsResult]] = await Promise.all([
    Promise.allSettled([getRepositories(), getModels()]),
    fetchMcpServers(),
  ]);
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

onMounted(load);
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
