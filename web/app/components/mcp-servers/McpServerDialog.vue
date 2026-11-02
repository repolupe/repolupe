<template>
  <GenericSaveDialog :title="current ? $t('mcpServers.dialog.editTitle') : $t('mcpServers.newServer')" v-model="dialog"
                     :loading="props.loading" @submit="submit">
    <v-text-field v-model="name" @keydown.enter="submit" :label="`${$t('common.name')}*`" placeholder="GitHub"
                  prepend-icon="mdi-label" class="mb-2" :disabled="props.loading" :counter="MAX_NAME_LENGTH" />

    <v-text-field v-model="url" @keydown.enter="submit" :label="`${$t('mcpServers.dialog.url')}*`"
                  placeholder="https://mcp.example.com/mcp" persistent-placeholder :hint="current ? undefined : urlHint"
                  persistent-hint prepend-icon="mdi-link" class="mb-2" :disabled="props.loading || !!current" />

    <v-text-field v-if="!current" v-model="token" @keydown.enter="submit" :label="$t('mcpServers.dialog.tokenOptional')"
                  :hint="$t('mcpServers.dialog.tokenHint')" persistent-hint prepend-icon="mdi-key" class="mt-2"
                  :disabled="props.loading" autocomplete="off" :type="showToken ? 'text' : 'password'"
                  :append-inner-icon="showToken ? 'mdi-eye' : 'mdi-eye-off'" @click:append-inner="showToken = !showToken" />

    <p v-else class="text-caption text-medium-emphasis mt-2">
      {{ $t('mcpServers.dialog.fixedConnection') }}
    </p>

    <p v-if="props.loading && !current" class="text-caption text-medium-emphasis mt-4">
      {{ $t('mcpServers.dialog.connecting') }}
    </p>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {charCount, showSnackbar, trimmedOrNull} from "~/utils/utils";
import type {CreateMcpServerPayload} from "~/utils/api";
import {type McpServerDto, UserRole} from "~/utils/model";
import {useUser} from "~/composables/states";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

/** Assumed like the other names of the API. */
const MAX_NAME_LENGTH = 100;

/** What the dialog submits. When editing, only `name` can change. */
export type McpServerFields = CreateMcpServerPayload;

const {t} = useI18n();
const user = useUser();

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', value: McpServerFields): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

/** The server being edited, `null` when adding one. */
const current = ref<McpServerDto | null>(null);
const name = ref('');
const url = ref('');
const token = ref('');
const showToken = ref(false);

const urlHint = computed(() => user.value?.role === UserRole.ADMIN
    ? t('mcpServers.dialog.urlHintAdmin')
    : t('mcpServers.dialog.urlHintUser'));

const submit = () => {
  if (props.loading) {
    return;
  }

  const trimmedName = name.value.trim();
  if (!trimmedName) {
    showSnackbar(t('common.missingName'));
    return;
  }
  if (charCount(trimmedName) > MAX_NAME_LENGTH) {
    showSnackbar(t('common.nameTooLong', {max: MAX_NAME_LENGTH}));
    return;
  }

  const trimmedUrl = url.value.trim();
  if (!trimmedUrl) {
    showSnackbar(t('mcpServers.dialog.missingUrl'));
    return;
  }

  emit('submit', {name: trimmedName, url: trimmedUrl, token: trimmedOrNull(token.value)});
};

defineExpose({
  reset: () => {
    current.value = null;
    name.value = '';
    url.value = '';
    token.value = '';
    showToken.value = false;
  },
  load: (server: McpServerDto) => {
    current.value = server;
    name.value = server.name;
    url.value = server.url;
    token.value = '';
    showToken.value = false;
  },
});
</script>
