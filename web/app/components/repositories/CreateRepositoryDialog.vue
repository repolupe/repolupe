<template>
  <GenericSaveDialog :title="title" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-if="isRemote" v-model="remoteUrl" :label="$t('repositories.remoteUrl')" prepend-icon="mdi-link-variant"
                  placeholder="https://github.com/owner/repo.git" :hint="remoteUrlHint" persistent-hint
                  class="mb-2" :disabled="props.loading" @keydown.enter="submit" />

    <v-text-field v-model="name" :label="$t('common.name')" prepend-icon="mdi-tag" :counter="MAX_NAME_LENGTH"
                  :placeholder="suggestedName" persistent-placeholder
                  :disabled="props.loading" @keydown.enter="submit" />

    <v-textarea v-model="description" :label="$t('repositories.createDialog.descriptionOptional')" prepend-icon="mdi-text"
                :counter="MAX_DESCRIPTION_LENGTH" rows="2" auto-grow :disabled="props.loading"
                :hint="$t('repositories.createDialog.descriptionHint')" persistent-hint class="mb-2" />

    <template v-if="isRemote">
      <v-text-field v-model="branch" :label="$t('repositories.branch')" prepend-icon="mdi-source-branch"
                    :disabled="props.loading" @keydown.enter="submit" />

      <v-select v-model="pollIntervalSeconds" :items="pollIntervalItems" :label="$t('repositories.syncInterval')"
                prepend-icon="mdi-timer-sync-outline" :disabled="props.loading" />

      <v-text-field v-model="token" :label="$t('repositories.createDialog.tokenOptional')" prepend-icon="mdi-key" type="password"
                    autocomplete="off" persistent-hint :disabled="props.loading" @keydown.enter="submit"
                    :hint="$t('repositories.createDialog.tokenHint')" />
    </template>

    <v-checkbox v-model="allowCommits" :label="$t('repositories.allowCommits')"
                prepend-icon="mdi-pencil-outline" color="primary" class="mt-2" :disabled="props.loading"
                :hint="isRemote ? undefined : $t('repositories.createDialog.allowCommitsHintLocal')"
                :persistent-hint="!isRemote" />

    <p v-if="props.loading && isRemote" class="text-caption text-medium-emphasis mt-4">
      {{ $t('repositories.createDialog.checkingRemote') }}
    </p>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {charCount, pollIntervalOptions, showSnackbar, trimmedOrNull} from "~/utils/utils";
import type {CreateRepositoryPayload, RemoteSettings} from "~/utils/api";
import {UserRole} from "~/utils/model";
import {useUser} from "~/composables/states";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";
import type {RepositoryKind} from "~/components/repositories/RepositoryKindDialog.vue";
import {useI18n} from "#i18n";

const MAX_NAME_LENGTH = 100;
const MAX_DESCRIPTION_LENGTH = 2000;
const DEFAULT_BRANCH = 'main';
const DEFAULT_POLL_INTERVAL_SECONDS = 900;

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', payload: CreateRepositoryPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const {t} = useI18n();

const user = useUser();

const pollIntervalItems = computed(() => pollIntervalOptions());

const kind = ref<RepositoryKind>('REMOTE');
const name = ref('');
const description = ref('');
const remoteUrl = ref('');
const branch = ref(DEFAULT_BRANCH);
const pollIntervalSeconds = ref(DEFAULT_POLL_INTERVAL_SECONDS);
const token = ref('');
const allowCommits = ref(true);

const isRemote = computed(() => kind.value === 'REMOTE');

const title = computed(() => isRemote.value
    ? t('repositories.createDialog.titleRemote')
    : t('repositories.createDialog.titleLocal'));

/** `https://host/.../<owner>/<repo>.git` -> `<owner>/<repo>`, or null if the URL has no such path. */
const parseRepositoryName = (url: string): string | null => {
  let path: string;
  try {
    path = new URL(url).pathname;
  } catch {
    return null;
  }
  const segments = path.split('/').filter(s => s.length > 0);
  if (segments.length < 2) {
    return null;
  }
  const owner = segments[segments.length - 2]!;
  const repo = segments[segments.length - 1]!.replace(/\.git$/, '');
  return repo ? `${owner}/${repo}` : null;
}

/** Used as the name when the name field is left empty. */
const suggestedName = computed(() => {
  if (!isRemote.value) {
    return '';
  }
  const trimmedRemoteUrl = remoteUrl.value.trim();
  return parseRepositoryName(trimmedRemoteUrl) ?? trimmedRemoteUrl;
});

const remoteUrlHint = computed(() => user.value?.role === UserRole.ADMIN
    ? t('repositories.createDialog.remoteUrlHintAdmin')
    : t('repositories.createDialog.remoteUrlHintUser'));

const submit = () => {
  if (props.loading) {
    return;
  }

  const trimmedName = name.value.trim() || suggestedName.value;
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

  let remote: RemoteSettings | null = null;
  if (isRemote.value) {
    const trimmedRemoteUrl = remoteUrl.value.trim();
    if (!trimmedRemoteUrl) {
      showSnackbar(t('repositories.missingRemoteUrl'));
      return;
    }

    const trimmedBranch = branch.value.trim();
    if (!trimmedBranch) {
      showSnackbar(t('repositories.missingBranch'));
      return;
    }

    remote = {
      url: trimmedRemoteUrl,
      branch: trimmedBranch,
      poll_interval_seconds: pollIntervalSeconds.value,
      token: trimmedOrNull(token.value),
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
  reset: (newKind: RepositoryKind) => {
    kind.value = newKind;
    name.value = '';
    description.value = '';
    remoteUrl.value = '';
    branch.value = DEFAULT_BRANCH;
    pollIntervalSeconds.value = DEFAULT_POLL_INTERVAL_SECONDS;
    token.value = '';
    allowCommits.value = true;
  },
});
</script>
