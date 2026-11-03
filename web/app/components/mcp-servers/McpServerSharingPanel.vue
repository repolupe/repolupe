<template>
  <div>
    <v-expansion-panels v-model="open" variant="accordion" static>
      <v-expansion-panel value="sharing" elevation="0" class="sharing-panel">
        <v-expansion-panel-title class="py-2">
          <IconText icon="mdi-account-multiple-outline" :size="16">{{ $t('mcpServers.sharing.title') }}</IconText>
        </v-expansion-panel-title>
        <v-expansion-panel-text>
          <p class="text-medium-emphasis">{{ $t('mcpServers.sharing.description') }}</p>

          <v-progress-linear v-if="fetching" indeterminate color="primary" class="mt-4"/>
          <p v-else-if="users.length === 0" class="mt-4 text-medium-emphasis">
            {{ $t('mcpServers.sharing.notShared') }}
          </p>
          <div v-else class="mt-2">
            <div v-for="user in users" :key="user.user_id" class="user d-flex align-center ga-4 py-2">
              <div class="user-text flex-grow-1">
                <div>{{ user.user_name }}</div>
                <div class="text-caption text-medium-emphasis">
                  <template v-if="user.email">{{ user.email }}<span class="mx-2">•</span></template>
                  <span :title="formatDateTime(user.created_at)">
                    {{ $t('mcpServers.sharing.sharedAt', {relative: formatRelative(user.created_at)}) }}
                  </span>
                </div>
              </div>
              <v-btn @click="showRemoveDialog(user)" icon="mdi-account-remove" variant="text" size="small"
                     v-tooltip="$t('mcpServers.sharing.stopSharing')" :aria-label="$t('mcpServers.sharing.stopSharing')"/>
            </div>
          </div>

          <v-btn @click="showShareDialog" class="mt-4" variant="tonal" prepend-icon="mdi-share-variant"
                 :text="$t('mcpServers.sharing.share')"/>
        </v-expansion-panel-text>
      </v-expansion-panel>
    </v-expansion-panels>

    <ShareUserDialog ref="share-dialog" v-model="dialogShare" :loading="loading"
                     :title="$t('mcpServers.shareDialog.title')" :description="$t('mcpServers.shareDialog.description')"
                     :submit-text="$t('mcpServers.sharing.share')" @submit="doShare"/>

    <GenericConfirmDialog v-model="dialogRemove" :loading="loading" :title="$t('mcpServers.sharing.stopSharingTitle')"
                          :confirm-text="$t('mcpServers.sharing.stopSharing')" confirm-icon="mdi-account-remove"
                          @confirm="doRemove">
      <i18n-t scope="global" keypath="mcpServers.sharing.stopSharingText" tag="span">
        <template v-slot:name>
          <strong>{{ selectedUser?.user_name }}</strong>
        </template>
      </i18n-t>
    </GenericConfirmDialog>
  </div>
</template>

<script setup lang="ts">
import {ref, useTemplateRef, watch} from "vue";
import {useI18n} from "#i18n";
import {ErrorCode, type McpServerUserDto} from "~/utils/model";
import {addMcpServerUser, ApiError, errorMessage, getMcpServerUsers, removeMcpServerUser} from "~/utils/api";
import {formatDateTime, formatRelative, showSnackbar} from "~/utils/utils";
import IconText from "~/components/IconText.vue";
import GenericConfirmDialog from "~/components/dialogs/GenericConfirmDialog.vue";
import ShareUserDialog from "~/components/dialogs/ShareUserDialog.vue";

/** The users a server is shared with, for its owner. Loaded when first opened. */
const props = defineProps<{
  serverId: string,
}>();

const {t} = useI18n();

const shareDialog = useTemplateRef<InstanceType<typeof ShareUserDialog>>('share-dialog');

const open = ref<string | undefined>(undefined);
const fetched = ref(false);
const fetching = ref(false);
const loading = ref(false);
const users = ref<McpServerUserDto[]>([]);
const selectedUser = ref<McpServerUserDto | null>(null);

const dialogShare = ref(false);
const dialogRemove = ref(false);

const fetchData = async () => {
  try {
    fetching.value = true;
    users.value = await getMcpServerUsers(props.serverId);
    fetched.value = true;
  } catch (e) {
    showSnackbar(t('mcpServers.sharing.loadFailed', {error: errorMessage(e)}));
  } finally {
    fetching.value = false;
  }
};

watch(open, async (value) => {
  if (value && !fetched.value && !fetching.value) {
    await fetchData();
  }
});

const showShareDialog = () => {
  shareDialog.value!.reset();
  dialogShare.value = true;
};

const doShare = async (userNameOrEmail: string) => {
  loading.value = true;
  try {
    await addMcpServerUser(props.serverId, userNameOrEmail);
    dialogShare.value = false;
    await fetchData();
    showSnackbar(t('mcpServers.sharing.shared'));
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_USER) {
      showSnackbar(t('mcpServers.sharing.unknownUser'));
    } else {
      showSnackbar(t('mcpServers.sharing.shareFailed', {error: errorMessage(e)}));
    }
  } finally {
    loading.value = false;
  }
};

const showRemoveDialog = (user: McpServerUserDto) => {
  selectedUser.value = user;
  dialogRemove.value = true;
};

const doRemove = async () => {
  loading.value = true;
  try {
    await removeMcpServerUser(props.serverId, selectedUser.value!.user_id);
    dialogRemove.value = false;
    await fetchData();
    showSnackbar(t('mcpServers.sharing.stopped'));
  } catch (e) {
    showSnackbar(t('mcpServers.sharing.stopFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
};
</script>

<style scoped>
.sharing-panel {
  border: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
}

.user + .user {
  border-top: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
}

/* lets long names and emails shrink next to the button */
.user-text {
  min-width: 0;
  overflow-wrap: anywhere;
}
</style>
