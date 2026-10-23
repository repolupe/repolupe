<template>
  <GenericSaveDialog :title="$t('repositories.editDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-model="name" @keydown.enter="submit" :label="`${$t('common.name')}*`" prepend-icon="mdi-label"
                  :counter="MAX_NAME_LENGTH" class="mb-2" :disabled="loading"/>

    <v-textarea v-model="description" :label="$t('repositories.description')" prepend-icon="mdi-text"
                :counter="MAX_DESCRIPTION_LENGTH" :rows="2" auto-grow class="mb-2" :disabled="loading"/>

    <template v-if="isRemote">
      <v-text-field v-model="remoteUrl" @keydown.enter="submit" :label="`${$t('repositories.remoteUrl')}*`" prepend-icon="mdi-link"
                    placeholder="https://github.com/owner/repo.git" class="mb-2" :disabled="loading"/>

      <v-text-field v-model="branch" @keydown.enter="submit" :label="`${$t('repositories.branch')}*`" prepend-icon="mdi-source-branch"
                    placeholder="main" class="mb-2" :disabled="loading" />

      <v-select v-model="pollInterval" :items="pollIntervalItems" :label="$t('repositories.syncInterval')" prepend-icon="mdi-timer-sync"
                class="mb-2" :disabled="loading"/>
    </template>

    <v-checkbox v-model="allowCommits" :label="$t('repositories.allowCommits')" prepend-icon="mdi-pencil-outline"
                color="primary" class="mb-2" :disabled="loading"/>

    <template v-if="isRemote">
      <div class="text-subtitle-2 mb-1">{{ $t('repositories.accessToken') }}</div>
      <v-radio-group v-model="tokenAction" :disabled="loading" hide-details class="mb-2">
        <v-radio v-if="hadToken" value="KEEP"
                 :label="tokenHint ? $t('repositories.editDialog.keepTokenWithHint', {hint: tokenHint}) : $t('repositories.editDialog.keepToken')"/>
        <v-radio value="REMOVE" :label="hadToken ? $t('repositories.editDialog.removeToken') : $t('repositories.editDialog.noToken')"/>
        <v-radio value="SET" :label="$t('repositories.editDialog.setToken')"/>
      </v-radio-group>

      <v-text-field v-if="tokenAction === 'SET'" v-model="token" @keydown.enter="submit" :label="`${$t('repositories.editDialog.newToken')}*`"
                    prepend-icon="mdi-key" :type="showToken ? 'text' : 'password'" autocomplete="off"
                    :append-inner-icon="showToken ? 'mdi-eye' : 'mdi-eye-off'"
                    @click:append-inner="showToken = !showToken" class="mb-2" :disabled="loading"
                    :hint="$t('repositories.editDialog.newTokenHint')" persistent-hint/>

      <v-alert v-if="hadToken && tokenAction === 'KEEP' && hostChanged" type="warning" variant="tonal" density="compact">
        {{ $t('repositories.editDialog.hostChanged') }}
      </v-alert>
    </template>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import type {RepositoryDto} from "~/utils/model";
import type {RemoteSettingsChange, TokenChange, UpdateRepositoryPayload} from "~/utils/api";
import {charCount, formatPollInterval, pollIntervalOptions, showSnackbar, trimmedOrNull} from "~/utils/utils";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";
import {useI18n} from "#i18n";

const MAX_NAME_LENGTH = 100;
const MAX_DESCRIPTION_LENGTH = 2000;

type TokenAction = TokenChange['action'];

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', value: UpdateRepositoryPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const {t} = useI18n();

// A local repository stays local, and one with a remote keeps it.
const isRemote = ref(true);
const name = ref('');
const description = ref('');
const remoteUrl = ref('');
const branch = ref('');
const pollInterval = ref(60);
const tokenAction = ref<TokenAction>('REMOVE');
const token = ref('');
const showToken = ref(false);
const allowCommits = ref(false);

const originalRemoteUrl = ref('');
const originalPollInterval = ref<number | null>(null);
const hadToken = ref(false);
const tokenHint = ref<string | null>(null);

// A value set through the API may not be one of the options.
const pollIntervalItems = computed(() => {
  const options = pollIntervalOptions();
  const current = originalPollInterval.value;
  if (current === null || options.some(o => o.value === current)) {
    return options;
  }
  return [...options, {title: formatPollInterval(current), value: current}]
      .sort((a, b) => a.value - b.value);
});

const originOf = (url: string): string | null => {
  try {
    return new URL(url.trim()).origin;
  } catch {
    return null;
  }
};

// Mirrors the server, which compares the origins (scheme, host and port).
const hostChanged = computed(() => {
  const next = originOf(remoteUrl.value);
  return next !== null && next !== originOf(originalRemoteUrl.value);
});

const submit = () => {
  const trimmedName = name.value.trim();
  if (!trimmedName) {
    showSnackbar(t('common.missingName'));
    return;
  }
  if (charCount(trimmedName) > MAX_NAME_LENGTH) {
    showSnackbar(t('common.nameTooLong', {max: MAX_NAME_LENGTH}));
    return;
  }
  if (charCount(description.value.trim()) > MAX_DESCRIPTION_LENGTH) {
    showSnackbar(t('repositories.descriptionTooLong', {max: MAX_DESCRIPTION_LENGTH}));
    return;
  }

  let remote: RemoteSettingsChange | null = null;
  if (isRemote.value) {
    if (!remoteUrl.value.trim()) {
      showSnackbar(t('repositories.missingRemoteUrl'));
      return;
    }
    if (!branch.value.trim()) {
      showSnackbar(t('repositories.missingBranch'));
      return;
    }

    let tokenChange: TokenChange;
    switch (tokenAction.value) {
      case 'KEEP':
        tokenChange = {action: 'KEEP'};
        break;
      case 'REMOVE':
        tokenChange = {action: 'REMOVE'};
        break;
      case 'SET':
        if (!token.value.trim()) {
          showSnackbar(t('repositories.editDialog.missingToken'));
          return;
        }
        tokenChange = {action: 'SET', value: token.value.trim()};
        break;
    }

    remote = {
      url: remoteUrl.value.trim(),
      branch: branch.value.trim(),
      poll_interval_seconds: pollInterval.value,
      token: tokenChange,
    };
  }

  emit('submit', {
    name: trimmedName,
    description: trimmedOrNull(description.value),
    remote,
    allow_commits: allowCommits.value,
  });
}

defineExpose({
  load: (repository: RepositoryDto) => {
    name.value = repository.name;
    description.value = repository.description ?? '';
    const remote = repository.remote;
    isRemote.value = remote !== null;
    remoteUrl.value = remote?.url ?? '';
    branch.value = remote?.branch ?? '';
    pollInterval.value = remote?.poll_interval_seconds ?? 60;
    originalRemoteUrl.value = remote?.url ?? '';
    originalPollInterval.value = remote?.poll_interval_seconds ?? null;
    hadToken.value = !!remote?.token;
    tokenHint.value = remote?.token?.hint ?? null;
    tokenAction.value = hadToken.value ? 'KEEP' : 'REMOVE';
    token.value = '';
    showToken.value = false;
    allowCommits.value = repository.allow_commits;
  },
});
</script>
