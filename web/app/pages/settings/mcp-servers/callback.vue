<template>
  <MainContainer :title="$t('mcpServers.callback.title')"
                 :parents="[{title: $t('settings.title'), to: '/settings'}, {title: $t('mcpServers.title'), to: '/settings/mcp-servers'}]">
    <v-card v-if="error === null">
      <v-card-text class="d-flex align-center py-8">
        <v-progress-circular indeterminate color="primary" size="24" width="3" class="mr-4" />
        {{ $t('mcpServers.callback.completing') }}
      </v-card-text>
    </v-card>

    <template v-else>
      <v-alert type="error" variant="tonal" :title="$t('mcpServers.callback.failedTitle')" class="callback-error">
        {{ error }}
      </v-alert>
      <v-btn to="/settings/mcp-servers" replace class="mt-6" color="primary" prepend-icon="mdi-arrow-left"
             :text="$t('mcpServers.callback.back')" />
    </template>
  </MainContainer>
</template>

<script lang="ts">
/**
 * The `state` already sent to the API, kept outside the component so the sign-in is completed only once even if the
 * page is set up again, e.g. by navigating back to it. The API accepts a state only once anyway.
 */
let completedState: string | null = null;
</script>

<script setup lang="ts">
import {onMounted, ref} from "vue";
import {navigateTo, useRoute} from "#app";
import {useI18n} from "#i18n";
import {ErrorCode, McpServerStatus} from "~/utils/model";
import {ApiError, completeMcpAuthorization, errorDetail} from "~/utils/api";
import {showSnackbar} from "~/utils/utils";
import MainContainer from "~/components/MainContainer.vue";

const {t} = useI18n();
const route = useRoute();

/** Why signing in failed, `null` while it is completed. */
const error = ref<string | null>(null);

/** A query parameter the authorization server sent, `null` if it is missing or empty. */
const param = (name: string): string | null => {
  const value = route.query[name];
  const first = Array.isArray(value) ? value[0] : value;
  return first ? first : null;
};

const complete = async () => {
  const oauthError = param('error');
  if (oauthError) {
    // the text of the authorization server, e.g. when the user denied access
    const description = param('error_description');
    error.value = oauthError === 'access_denied' && !description
        ? t('mcpServers.callback.denied')
        : t('mcpServers.callback.serverError', {error: description ?? oauthError});
    return;
  }

  const state = param('state');
  const code = param('code');
  if (!state || !code) {
    error.value = t('mcpServers.callback.incomplete');
    return;
  }
  if (state === completedState) {
    await navigateTo('/settings/mcp-servers', {replace: true});
    return;
  }
  completedState = state;

  try {
    const server = await completeMcpAuthorization({state, code, iss: param('iss')});
    showSnackbar(server.status === McpServerStatus.READY
        ? t('mcpServers.callback.signedIn', {name: server.name})
        : t('mcpServers.callback.signedInNotReady', {name: server.name}));
    await navigateTo('/settings/mcp-servers', {replace: true});
  } catch (e) {
    error.value = e instanceof ApiError && e.code === ErrorCode.NOT_FOUND
        ? t('mcpServers.callback.expired')
        : t('mcpServers.callback.failed', {error: errorDetail(e)});
  }
};

onMounted(complete);
</script>

<style scoped>
.callback-error {
  overflow-wrap: anywhere;
}
</style>
