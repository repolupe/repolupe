<template>
  <MainContainer :title="$t('mcpServers.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <template v-slot:meta>
      <div style="max-width: 300px">
        <p class="text-h6 mb-4">{{ $t('mcpServers.page.count', servers.length) }}</p>

        <p class="text-medium-emphasis">{{ $t('mcpServers.page.intro') }}</p>
        <p class="mt-2 text-medium-emphasis">{{ $t('mcpServers.page.privacy') }}</p>
        <v-btn v-if="canManage" @click="showCreateDialog" class="mt-6" color="primary" prepend-icon="mdi-plus"
               :text="$t('mcpServers.newServer')" block />
      </div>
    </template>

    <v-progress-linear v-if="fetching && servers.length === 0" indeterminate color="primary" />

    <EmptyState v-else-if="servers.length === 0" icon="mdi-puzzle" :title="$t('mcpServers.page.emptyTitle')"
                :action-text="canManage ? $t('mcpServers.newServer') : undefined" @action="showCreateDialog">
      {{ canManage ? $t('mcpServers.page.emptyText') : $t('mcpServers.page.emptyTextShared') }}
    </EmptyState>

    <template v-else>
      <v-card v-for="server in servers" :key="server.id" class="mb-6">
        <v-card-item>
          <v-card-title>{{ server.name }}</v-card-title>
          <v-card-subtitle class="server-url" :title="server.url">{{ server.url }}</v-card-subtitle>

          <template v-slot:append>
            <template v-if="manages(server)">
              <v-btn @click="showUpdateDialog(server)" icon="mdi-pencil" variant="text"
                     v-tooltip="$t('mcpServers.page.editServer')" />
              <v-btn @click="showDeleteDialog(server)" icon="mdi-delete" variant="text"
                     v-tooltip="$t('mcpServers.page.deleteServer')" />
            </template>
            <v-btn v-else-if="server.shared" @click="showLeaveDialog(server)" icon="mdi-logout" variant="text"
                   v-tooltip="$t('mcpServers.page.leave')" />
          </template>
        </v-card-item>

        <v-card-text>
          <div class="d-flex align-center flex-wrap ga-3">
            <v-chip :color="statusInfo(server).color" :prepend-icon="statusInfo(server).icon" size="small" label>
              {{ statusInfo(server).label }}
            </v-chip>
            <v-chip v-if="server.status === McpServerStatus.READY && !isMcpServerUsed(server)" color="grey"
                    prepend-icon="mdi-chat-remove-outline" size="small" label>
              {{ $t('mcpServers.page.notUsed') }}
            </v-chip>
            <v-chip v-if="server.shared" prepend-icon="mdi-account-multiple" size="small" label
                    v-tooltip="$t('mcpServers.page.sharedWithYouHint')">
              {{ $t('mcpServers.page.sharedBy', {name: server.shared.owner_name}) }}
            </v-chip>
            <span class="text-caption text-medium-emphasis">
              <IconText :icon="authInfo(server).icon">{{ authInfo(server).label }}</IconText>
              <span class="mx-2">•</span>
              <span :title="formatDateTime(server.checked_at)">
                {{ $t('mcpServers.page.checked', {relative: formatRelative(server.checked_at)}) }}
              </span>
            </span>
          </div>

          <v-alert v-if="server.status === McpServerStatus.FAILED && server.last_error" type="error" variant="tonal"
                   density="compact" class="mt-4 server-error">
            {{ $t('mcpServers.page.lastError', {error: server.last_error}) }}
          </v-alert>
          <v-alert v-else-if="server.status === McpServerStatus.FAILED && server.shared" type="error" variant="tonal"
                   density="compact" class="mt-4">
            {{ $t('mcpServers.page.lastErrorShared') }}
          </v-alert>
          <v-alert v-else-if="server.status === McpServerStatus.AUTHORIZATION_REQUIRED" type="info" variant="tonal"
                   density="compact" class="mt-4">
            {{ isOwner(server) ? $t('mcpServers.page.signInRequired') : $t('mcpServers.page.signInRequiredShared') }}
          </v-alert>
          <v-alert v-if="server.shared && !server.shared.enabled" type="info" variant="tonal" density="compact"
                   class="mt-4">
            {{ $t('mcpServers.page.sharedOff', {name: server.shared.owner_name}) }}
          </v-alert>

          <v-expansion-panels v-if="server.tools.length !== 0" class="mt-4" variant="accordion" static>
            <v-expansion-panel elevation="0" class="tools-panel">
              <v-expansion-panel-title class="py-2">
                <IconText icon="mdi-puzzle-outline" :size="16">{{ mcpToolCountLabel(server) }}</IconText>
              </v-expansion-panel-title>
              <v-expansion-panel-text :class="{'server-off': !isMcpServerOn(server)}">
                <div class="d-flex align-center ga-4">
                  <div class="tool-text flex-grow-1 text-medium-emphasis">{{ $t('mcpServers.page.allTools') }}</div>
                  <v-checkbox :model-value="enabledMcpToolCount(server) === server.tools.length"
                              :indeterminate="enabledMcpToolCount(server) !== 0 && enabledMcpToolCount(server) !== server.tools.length"
                              @update:model-value="doToggleAllTools(server, !!$event)"
                              :aria-label="$t('mcpServers.page.allTools')" :disabled="busy !== null || !manages(server)"
                              color="primary" density="compact" hide-details class="flex-grow-0 flex-shrink-0" />
                </div>
                <v-divider class="my-2" />
                <div v-for="tool in server.tools" :key="tool.name" class="tool d-flex align-center ga-4">
                  <div class="tool-text flex-grow-1">
                    <div>
                      <code class="tool-name">{{ tool.name }}</code>
                      <span v-if="tool.title && tool.title !== tool.name" class="ml-2">{{ tool.title }}</span>
                    </div>
                    <div v-if="tool.description" class="tool-description text-caption text-medium-emphasis"
                         :title="tool.description">
                      {{ tool.description }}
                    </div>
                  </div>
                  <v-checkbox :model-value="isMcpToolEnabled(server, tool)"
                              @update:model-value="doToggleTool(server, tool, !!$event)" :aria-label="tool.name"
                              :disabled="busy !== null || !manages(server)" color="primary" density="compact"
                              hide-details class="flex-grow-0 flex-shrink-0" />
                </div>
              </v-expansion-panel-text>
            </v-expansion-panel>
          </v-expansion-panels>
          <p v-else-if="server.status === McpServerStatus.READY" class="mt-4 text-medium-emphasis">
            {{ $t('mcpServers.page.noTools') }}
          </p>

          <McpServerSharingPanel v-if="manages(server)" :server-id="server.id" class="mt-4" />
        </v-card-text>

        <v-card-actions v-if="manages(server)" class="flex-wrap">
          <v-btn v-if="server.status === McpServerStatus.AUTHORIZATION_REQUIRED" @click="startSignIn(server)"
                 color="primary" variant="elevated" prepend-icon="mdi-login" :text="$t('mcpServers.page.signIn')"
                 :loading="isBusy(server, 'signIn')" :disabled="busy !== null" />
          <v-btn v-else-if="server.auth === McpServerAuth.OAUTH" @click="startSignIn(server)" prepend-icon="mdi-login"
                 :text="$t('mcpServers.page.signInAgain')" :loading="isBusy(server, 'signIn')" :disabled="busy !== null" />
          <v-btn @click="doRefresh(server)" prepend-icon="mdi-refresh" :text="$t('common.refresh')"
                 :loading="isBusy(server, 'refresh')" :disabled="busy !== null" />
          <v-spacer />
          <v-checkbox :model-value="server.enabled" @update:model-value="doToggle(server, !!$event)"
                      :label="$t('mcpServers.page.useInChats')" :disabled="busy !== null" color="primary"
                      density="compact" hide-details class="flex-grow-0 mx-2" />
        </v-card-actions>
        <v-card-actions v-else-if="server.shared">
          <v-spacer />
          <v-checkbox :model-value="server.shared.enabled" @update:model-value="doToggleShared(server, !!$event)"
                      :label="$t('mcpServers.page.useInChats')" :disabled="busy !== null" color="primary"
                      density="compact" hide-details class="flex-grow-0 mx-2" />
        </v-card-actions>
      </v-card>
    </template>

    <McpServerDialog ref="server-dialog" v-model="dialogServer" :loading="loading" @submit="doSave" />

    <GenericDeleteDialog :title="$t('mcpServers.page.deleteTitle')" v-model="dialogDelete" :loading="loading"
                         @delete="doDelete">
      <i18n-t scope="global" keypath="mcpServers.page.deleteText" tag="span">
        <template v-slot:name><b>{{ selectedServer?.name }}</b></template>
      </i18n-t>
    </GenericDeleteDialog>

    <GenericConfirmDialog :title="$t('mcpServers.page.leaveTitle')" v-model="dialogLeave" :loading="loading"
                          :confirm-text="$t('mcpServers.page.leave')" confirm-icon="mdi-logout" @confirm="doLeave">
      <i18n-t scope="global" keypath="mcpServers.page.leaveText" tag="span">
        <template v-slot:name><b>{{ selectedServer?.name }}</b></template>
      </i18n-t>
    </GenericConfirmDialog>

    <GenericConfirmDialog :title="$t('mcpServers.page.signInTitle', {name: selectedServer?.name ?? ''})"
                          v-model="dialogSignIn" :loading="busy !== null" :confirm-text="$t('mcpServers.page.signIn')"
                          confirm-icon="mdi-login" @confirm="startSignIn(selectedServer!)">
      {{ $t('mcpServers.page.signInText', {name: selectedServer?.name ?? ''}) }}
    </GenericConfirmDialog>
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, onMounted, ref, useTemplateRef} from "vue";
import {useRouter} from "#app";
import {useI18n} from "#i18n";
import {ErrorCode, McpServerAuth, type McpServerDto, McpServerStatus, type McpToolDto} from "~/utils/model";
import {
  ApiError,
  authorizeMcpServer,
  createMcpServer,
  deleteMcpServer,
  errorDetail,
  errorMessage,
  getMcpServers,
  refreshMcpServer,
  removeMcpServerUser,
  updateMcpServer,
  updateMcpServerUser,
} from "~/utils/api";
import {
  enabledMcpToolCount,
  formatDateTime,
  formatRelative,
  isMcpServerOn,
  isMcpServerUsed,
  isMcpToolEnabled,
  mcpServerStatusLabel,
  mcpToolCountLabel,
  showSnackbar,
} from "~/utils/utils";
import {useUser} from "~/composables/states";
import MainContainer from "~/components/MainContainer.vue";
import EmptyState from "~/components/EmptyState.vue";
import IconText from "~/components/IconText.vue";
import GenericDeleteDialog from "~/components/dialogs/GenericDeleteDialog.vue";
import GenericConfirmDialog from "~/components/dialogs/GenericConfirmDialog.vue";
import McpServerDialog, {type McpServerFields} from "~/components/mcp-servers/McpServerDialog.vue";
import McpServerSharingPanel from "~/components/mcp-servers/McpServerSharingPanel.vue";

type BusyAction = 'signIn' | 'refresh' | 'toggle' | 'toggleTool';

const {t} = useI18n();
const router = useRouter();
const user = useUser();

const serverDialog = useTemplateRef<InstanceType<typeof McpServerDialog>>('server-dialog');

const fetching = ref(true);
/** While the dialog to add, edit or delete a server saves. */
const loading = ref(false);
/** An action on one server's card, one at a time. */
const busy = ref<{ id: string, action: BusyAction } | null>(null);
const servers = ref<McpServerDto[]>([]);
const selectedServer = ref<McpServerDto | null>(null);

const dialogServer = ref(false);
const dialogDelete = ref(false);
const dialogSignIn = ref(false);
const dialogLeave = ref(false);

/** Users without the permission still see their servers and the ones shared with them, and turn the latter on. */
const canManage = computed(() => !!user.value?.can_manage_mcp_servers);

/** Only the owner manages a server, users it is shared with only use it. */
const isOwner = (server: McpServerDto) => server.owner_id === user.value?.id;

const manages = (server: McpServerDto) => isOwner(server) && canManage.value;

const isBusy = (server: McpServerDto, action: BusyAction) =>
    busy.value?.id === server.id && busy.value.action === action;

/** `disabled_tools` with every tool the server lists turned on, keeping the names it no longer lists. */
const withAllToolsOn = (server: McpServerDto) =>
    server.disabled_tools.filter(name => !server.tools.some(tool => tool.name === name));

const statusInfo = (server: McpServerDto) => {
  const label = mcpServerStatusLabel(server.status);
  switch (server.status) {
    case McpServerStatus.READY:
      return {label, color: 'green', icon: 'mdi-check-circle'};
    case McpServerStatus.AUTHORIZATION_REQUIRED:
      return {label, color: 'orange', icon: 'mdi-account-lock'};
    case McpServerStatus.FAILED:
      return {label, color: 'red', icon: 'mdi-alert-circle'};
    default:
      return {label, color: 'grey', icon: 'mdi-help-circle'};
  }
};

const authInfo = (server: McpServerDto) => {
  switch (server.auth) {
    case McpServerAuth.NONE:
      return {label: t('mcpServers.page.authNone'), icon: 'mdi-lock-open-variant-outline'};
    case McpServerAuth.OAUTH:
      return {label: t('mcpServers.page.authOAuth'), icon: 'mdi-account-check-outline'};
    default:
      return {
        label: server.token_hint ? t('mcpServers.page.authTokenHint', {hint: server.token_hint}) : t('mcpServers.page.authToken'),
        icon: 'mdi-key-outline',
      };
  }
};

/**
 * Like {@link errorDetail}, telling what an MCP endpoint is when the server could not be connected to. Adding a server
 * connects to it, so the API's message tells why that failed.
 */
const createErrorMessage = (e: unknown): string =>
    e instanceof ApiError && e.code === ErrorCode.REMOTE_UNREACHABLE
        ? t('mcpServers.unreachable', {error: errorDetail(e)})
        : errorDetail(e);

const replaceServer = (server: McpServerDto) => {
  servers.value = servers.value.map(s => s.id === server.id ? server : s);
};

const fetchData = async () => {
  try {
    fetching.value = true;
    servers.value = await getMcpServers();
  } catch (e) {
    showSnackbar(t('mcpServers.page.loadFailed', {error: errorMessage(e)}));
  } finally {
    fetching.value = false;
  }
};

const showCreateDialog = () => {
  selectedServer.value = null;
  serverDialog.value!.reset();
  dialogServer.value = true;
};

const showUpdateDialog = (server: McpServerDto) => {
  selectedServer.value = server;
  serverDialog.value!.load(server);
  dialogServer.value = true;
};

const showDeleteDialog = (server: McpServerDto) => {
  selectedServer.value = server;
  dialogDelete.value = true;
};

const showLeaveDialog = (server: McpServerDto) => {
  selectedServer.value = server;
  dialogLeave.value = true;
};

/** Asks to sign in right away, e.g. after adding a server that requires it. */
const offerSignIn = (server: McpServerDto) => {
  selectedServer.value = server;
  dialogSignIn.value = true;
};

const doSave = async (fields: McpServerFields) => {
  const editing = selectedServer.value;
  loading.value = true;
  try {
    let server: McpServerDto;
    if (editing) {
      server = await updateMcpServer(editing.id, {
        name: fields.name,
        enabled: editing.enabled,
        disabled_tools: editing.disabled_tools,
      });
      showSnackbar(t('mcpServers.page.updated'));
    } else {
      server = await createMcpServer(fields);
      showSnackbar(t('mcpServers.page.created'));
    }
    dialogServer.value = false;
    await fetchData();
    if (!editing && server.status === McpServerStatus.AUTHORIZATION_REQUIRED) {
      offerSignIn(server);
    }
  } catch (e) {
    // changing a server does not connect to it
    showSnackbar(editing
        ? t('mcpServers.page.saveFailed', {error: errorMessage(e)})
        : t('mcpServers.page.createFailed', {error: createErrorMessage(e)}));
  } finally {
    loading.value = false;
  }
};

const doDelete = async () => {
  loading.value = true;
  try {
    await deleteMcpServer(selectedServer.value!.id);
    dialogDelete.value = false;
    showSnackbar(t('mcpServers.page.deleted'));
    await fetchData();
  } catch (e) {
    showSnackbar(t('mcpServers.page.deleteFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
};

const doLeave = async () => {
  const server = selectedServer.value!;
  loading.value = true;
  try {
    await removeMcpServerUser(server.id, user.value!.id);
    dialogLeave.value = false;
    showSnackbar(t('mcpServers.page.left', {name: server.name}));
    await fetchData();
  } catch (e) {
    showSnackbar(t('mcpServers.page.leaveFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
};

/**
 * Turns the owner's server on or off for their own chats. The users it is shared with turn it on or off for theirs, and
 * its tools are the same for everyone, so this leaves them alone.
 */
const doToggle = async (server: McpServerDto, enabled: boolean) => {
  busy.value = {id: server.id, action: 'toggle'};
  try {
    replaceServer(await updateMcpServer(server.id, {
      name: server.name,
      enabled,
      disabled_tools: server.disabled_tools,
    }));
    showSnackbar(t(enabled ? 'mcpServers.page.enabled' : 'mcpServers.page.disabled', {name: server.name}));
  } catch (e) {
    showSnackbar(t('mcpServers.page.toggleFailed', {error: errorMessage(e)}));
  } finally {
    busy.value = null;
  }
};

/** Turns a server shared with the user on or off for their chats. */
const doToggleShared = async (server: McpServerDto, enabled: boolean) => {
  busy.value = {id: server.id, action: 'toggle'};
  try {
    await updateMcpServerUser(server.id, user.value!.id, enabled);
    replaceServer({...server, shared: {...server.shared!, enabled}});
    showSnackbar(t(enabled ? 'mcpServers.page.enabled' : 'mcpServers.page.disabled', {name: server.name}));
  } catch (e) {
    // tells when the user has as many servers as they may use
    showSnackbar(t('mcpServers.page.toggleFailed', {error: errorDetail(e)}));
  } finally {
    busy.value = null;
  }
};

/**
 * Saves which tools are off, for everyone who uses the server. Whether the owner uses it stays, since the users it is
 * shared with may use it while the owner does not.
 */
const saveDisabledTools = async (server: McpServerDto, disabledTools: string[]) => {
  replaceServer(await updateMcpServer(server.id, {
    name: server.name,
    enabled: server.enabled,
    disabled_tools: disabledTools,
  }));
};

/** Names the server no longer lists stay in `disabled_tools`, so those tools stay off if they return. */
const doToggleTool = async (server: McpServerDto, tool: McpToolDto, enabled: boolean) => {
  busy.value = {id: server.id, action: 'toggleTool'};
  try {
    const disabledTools = enabled
        ? server.disabled_tools.filter(name => name !== tool.name)
        : [...server.disabled_tools, tool.name];
    await saveDisabledTools(server, disabledTools);
    showSnackbar(t(enabled ? 'mcpServers.page.toolEnabled' : 'mcpServers.page.toolDisabled', {name: tool.name}));
  } catch (e) {
    showSnackbar(t('mcpServers.page.toggleToolFailed', {error: errorMessage(e)}));
  } finally {
    busy.value = null;
  }
};

/** Like {@link doToggleTool}, for every tool the server lists. */
const doToggleAllTools = async (server: McpServerDto, enabled: boolean) => {
  busy.value = {id: server.id, action: 'toggleTool'};
  try {
    const disabledTools = enabled
        ? withAllToolsOn(server)
        : [...new Set([...server.disabled_tools, ...server.tools.map(tool => tool.name)])];
    await saveDisabledTools(server, disabledTools);
    showSnackbar(t(enabled ? 'mcpServers.page.allToolsEnabled' : 'mcpServers.page.allToolsDisabled', {name: server.name}));
  } catch (e) {
    showSnackbar(t('mcpServers.page.toggleAllToolsFailed', {error: errorMessage(e)}));
  } finally {
    busy.value = null;
  }
};

const doRefresh = async (server: McpServerDto) => {
  busy.value = {id: server.id, action: 'refresh'};
  try {
    const updated = await refreshMcpServer(server.id);
    replaceServer(updated);
    switch (updated.status) {
      case McpServerStatus.READY:
        showSnackbar(t('mcpServers.page.refreshed', updated.tools.length));
        break;
      case McpServerStatus.AUTHORIZATION_REQUIRED:
        showSnackbar(t('mcpServers.page.refreshedSignIn', {name: updated.name}));
        break;
      default:
        showSnackbar(t('mcpServers.page.refreshedFailed', {name: updated.name}));
    }
  } catch (e) {
    showSnackbar(t('mcpServers.page.refreshFailed', {error: errorMessage(e)}));
  } finally {
    busy.value = null;
  }
};

/** Absolute, and also right if the app is served under a base path, since the router's URLs include it. */
const callbackUrl = (): string =>
    new URL(router.resolve('/settings/mcp-servers/callback').href, window.location.origin).href;

/** Leaves the app for the server's sign-in page, which sends the user back to `pages/settings/mcp-servers/callback.vue`. */
const startSignIn = async (server: McpServerDto) => {
  busy.value = {id: server.id, action: 'signIn'};
  try {
    const authorizationUrl = new URL(await authorizeMcpServer(server.id, callbackUrl()));
    // it comes from the MCP server, so never run it as a `javascript:` URL
    if (authorizationUrl.protocol !== 'https:' && authorizationUrl.protocol !== 'http:') {
      throw new Error('unexpected authorization URL');
    }
    window.location.assign(authorizationUrl.href);
  } catch (e) {
    showSnackbar(t('mcpServers.page.signInFailed', {error: errorDetail(e)}));
  } finally {
    busy.value = null;
  }
};

onMounted(async () => {
  await fetchData();
});
</script>

<style scoped>
.server-url {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.server-error {
  overflow-wrap: anywhere;
}

.tools-panel {
  border: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
}

.tool + .tool {
  margin-top: 12px;
}

/* lets long descriptions shrink next to the switch */
.tool-text {
  min-width: 0;
}

.tool-name {
  font-weight: 600;
}

/* the tools are not used in the user's chats while the server is off for them */
.server-off .tool-text {
  opacity: var(--v-disabled-opacity);
}

/* descriptions can be long, the full text is in the tooltip */
.tool-description {
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
</style>
