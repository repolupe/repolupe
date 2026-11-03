<template>
  <GenericSaveDialog :title="current ? $t('mcpServers.dialog.editTitle') : $t('mcpServers.newServer')" v-model="dialog"
                     :loading="props.loading" @submit="submit">
    <v-combobox :model-value="name" @update:model-value="onNameChange" v-model:menu="nameMenu"
                @update:focused="onNameFocused" :items="nameSuggestions" item-title="name" item-value="name"
                :return-object="false" hide-no-data :label="`${$t('common.name')}*`" placeholder="GitHub"
                prepend-icon="mdi-label" class="mb-2" :disabled="props.loading" :counter="MAX_NAME_LENGTH">
      <template v-slot:item="{props: itemProps, item}">
        <v-list-item v-bind="itemProps" :subtitle="kindLabel(item.raw.kind)">
          <template v-slot:prepend>
            <span :class="`fi fi-${item.raw.country_code.toLowerCase()}`" class="mr-4" />
          </template>
        </v-list-item>
      </template>
    </v-combobox>

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
import "flag-icons/css/flag-icons.min.css";
import {useI18n} from "#i18n";
import {charCount, showSnackbar, trimmedOrNull} from "~/utils/utils";
import {type CreateMcpServerPayload, getMcpServerSuggestions} from "~/utils/api";
import {type McpServerDto, McpServerKind, type McpServerSuggestionDto, UserRole} from "~/utils/model";
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

const nameMenu = ref(false);

/** Loaded when the dialog first opens to add a server. */
const suggestions = ref<McpServerSuggestionDto[]>([]);

const loadSuggestions = async () => {
  if (suggestions.value.length > 0) {
    return;
  }
  try {
    suggestions.value = await getMcpServerSuggestions();
  } catch {
    // Only a convenience: without them, the URL is entered by hand.
  }
};

/** Only offered when adding a server, since choosing one fills in the URL, which can't be changed later. */
const nameSuggestions = computed(() => current.value ? [] : suggestions.value);

/** `undefined` for kinds of a newer server, which then show no subtitle. */
const kindLabel = (kind: McpServerKind): string | undefined => {
  switch (kind) {
    case McpServerKind.SEARCH:
      return t('mcpServers.kind.search');
    case McpServerKind.WEB_SCRAPING:
      return t('mcpServers.kind.webScraping');
    case McpServerKind.DOCUMENTATION:
      return t('mcpServers.kind.documentation');
    case McpServerKind.DEV_TOOLS:
      return t('mcpServers.kind.devTools');
    case McpServerKind.CLOUD:
      return t('mcpServers.kind.cloud');
    case McpServerKind.DATABASE:
      return t('mcpServers.kind.database');
    case McpServerKind.OBSERVABILITY:
      return t('mcpServers.kind.observability');
    case McpServerKind.PROJECT_MANAGEMENT:
      return t('mcpServers.kind.projectManagement');
    case McpServerKind.PRODUCTIVITY:
      return t('mcpServers.kind.productivity');
    case McpServerKind.CRM:
      return t('mcpServers.kind.crm');
    case McpServerKind.PAYMENTS:
      return t('mcpServers.kind.payments');
    case McpServerKind.FINANCE:
      return t('mcpServers.kind.finance');
    case McpServerKind.DESIGN:
      return t('mcpServers.kind.design');
    case McpServerKind.AUTOMATION:
      return t('mcpServers.kind.automation');
    case McpServerKind.KNOWLEDGE:
      return t('mcpServers.kind.knowledge');
    case McpServerKind.MAPS:
      return t('mcpServers.kind.maps');
    case McpServerKind.TRAVEL:
      return t('mcpServers.kind.travel');
  }
};

const onNameFocused = (focused: boolean) => {
  if (focused && nameSuggestions.value.length > 0) {
    nameMenu.value = true;
  }
};

/** Fills in the URL when the name is one of the suggestions. */
const onNameChange = (value: string | null) => {
  name.value = value ?? '';
  const suggestion = nameSuggestions.value.find(s => s.name === value);
  if (suggestion) {
    url.value = suggestion.url;
  }
};

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
    loadSuggestions();
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
