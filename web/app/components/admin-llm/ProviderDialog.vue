<template>
  <GenericSaveDialog :title="current ? $t('admin.llm.providerDialog.editTitle') : $t('admin.llm.newProvider')" v-model="dialog"
                     :loading="props.loading" @submit="submit">
    <v-combobox :model-value="name" @update:model-value="onNameChange" v-model:menu="nameMenu"
                @update:focused="onNameFocused" :items="nameSuggestions" item-title="name" item-value="name"
                :return-object="false" hide-no-data :label="`${$t('common.name')}*`" placeholder="Anthropic"
                prepend-icon="mdi-label" class="mb-2" :disabled="loading" :counter="MAX_NAME_LENGTH"
                :rules="[rules.name]">
      <template v-slot:item="{props: itemProps, item}">
        <v-list-item v-bind="itemProps">
          <template v-slot:prepend>
            <!-- without a country, the empty `fi` keeps the titles aligned -->
            <span :class="['fi', item.raw.country_code && `fi-${item.raw.country_code.toLowerCase()}`]"
                  class="mr-4" />
          </template>
          <template v-if="suggestionSubtitle(item.raw)" v-slot:subtitle>
            <v-icon v-if="suggestionSubtitle(item.raw)!.icon" :icon="suggestionSubtitle(item.raw)!.icon" size="12" />
            {{ suggestionSubtitle(item.raw)!.text }}
          </template>
        </v-list-item>
      </template>
    </v-combobox>

    <v-select v-model="apiFormat" :items="API_FORMAT_OPTIONS" :label="`${$t('admin.llm.providerDialog.apiFormat')}*`"
              prepend-icon="mdi-api" class="mb-2" :disabled="loading" />

    <v-autocomplete v-model="currency" :items="currencies" :label="$t('admin.llm.providerDialog.currency')" prepend-icon="mdi-cash"
                    class="mb-2" :disabled="loading" clearable>
      <template v-slot:prepend-inner>
        <span v-if="currencyFlag" :class="`fi fi-${currencyFlag}`" class="mr-1" />
      </template>
      <template v-slot:item="{props: itemProps, item}">
        <v-list-item v-bind="itemProps">
          <template v-slot:prepend>
            <!-- without a flag, the empty `fi` keeps the titles aligned -->
            <span :class="['fi', item.raw.flag && `fi-${item.raw.flag}`]" class="mr-4" />
          </template>
        </v-list-item>
      </template>
    </v-autocomplete>

    <v-text-field v-model="baseUrl" @keydown.enter="submit" :label="$t('admin.llm.providerDialog.baseUrl')"
                  :placeholder="DEFAULT_BASE_URLS[apiFormat]" persistent-placeholder
                  prepend-icon="mdi-link" class="mb-2" :disabled="loading" />

    <template v-if="!current">
      <v-text-field v-model="apiKey" @keydown.enter="submit" :label="$t('admin.llm.providerDialog.apiKey')"
                    prepend-icon="mdi-key" :disabled="loading" autocomplete="off"
                    :type="showKey ? 'text' : 'password'"
                    :append-inner-icon="showKey ? 'mdi-eye' : 'mdi-eye-off'"
                    @click:append-inner="showKey = !showKey" />
    </template>

    <template v-else>
      <div class="d-flex align-center mt-2">
        <v-icon class="mr-4 text-medium-emphasis">mdi-key</v-icon>
        <span class="text-body-1">{{ $t('admin.llm.providerDialog.apiKey') }}</span>
        <span class="ml-2 text-medium-emphasis">{{ $t('admin.llm.providerDialog.currentKey', {key: currentKeyText}) }}</span>
      </div>
      <v-radio-group v-model="keyAction" :disabled="loading" class="ml-10 mt-1" hide-details>
        <v-radio v-if="current.api_key" :label="$t('admin.llm.providerDialog.keepKey')" value="KEEP" />
        <v-radio :label="current.api_key ? $t('admin.llm.providerDialog.removeKey') : $t('admin.llm.providerDialog.noKey')" value="REMOVE" />
        <v-radio :label="$t('admin.llm.providerDialog.setKey')" value="SET" />
      </v-radio-group>

      <v-text-field v-if="keyAction === 'SET'" v-model="apiKey" @keydown.enter="submit" :label="`${$t('admin.llm.providerDialog.newKey')}*`"
                    class="ml-10 mt-2" :disabled="loading" autocomplete="off"
                    :type="showKey ? 'text' : 'password'"
                    :append-inner-icon="showKey ? 'mdi-eye' : 'mdi-eye-off'"
                    @click:append-inner="showKey = !showKey" />

      <v-alert v-if="keyAction === 'KEEP' && hostChanged" type="warning" variant="tonal" density="compact"
               class="mt-4">
        {{ $t('admin.llm.providerDialog.hostChanged') }}
      </v-alert>
    </template>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import "flag-icons/css/flag-icons.min.css";
import {charCount, currencyOptions, showSnackbar, trimmedOrNull} from "~/utils/utils";
import {type ApiKeyChange, getLlmProviderSuggestions, type UpdateLlmProviderPayload} from "~/utils/api";
import {LlmApiFormat, type LlmProviderDto, type LlmProviderSuggestionDto} from "~/utils/model";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";
import {useI18n} from "#i18n";

const MAX_NAME_LENGTH = 100;
const DEFAULT_CURRENCY = 'USD';

/** Mirrors `LlmApiFormat::default_base_url` in the API. */
const DEFAULT_BASE_URLS: Record<LlmApiFormat, string> = {
  [LlmApiFormat.ANTHROPIC]: 'https://api.anthropic.com',
  [LlmApiFormat.OPENAI]: 'https://api.openai.com/v1',
};

const API_FORMAT_OPTIONS = [
  {title: 'OpenAI', value: LlmApiFormat.OPENAI},
  {title: 'Anthropic', value: LlmApiFormat.ANTHROPIC},
];

type KeyAction = ApiKeyChange['action'];

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  /** On create, `api_key` is `SET` with the entered key, or `REMOVE` for none. */
  (e: 'submit', value: UpdateLlmProviderPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

/** The provider being edited, `null` when creating one. */
const current = ref<LlmProviderDto | null>(null);
const name = ref('');
const apiFormat = ref<LlmApiFormat>(LlmApiFormat.OPENAI);
const baseUrl = ref('');
const keyAction = ref<KeyAction>('SET');
const apiKey = ref('');
const showKey = ref(false);
const currency = ref<string | null>(DEFAULT_CURRENCY);

const currencies = computed(() => currencyOptions(current.value?.currency ?? null));
const currencyFlag = computed(() => currencies.value.find(c => c.value === currency.value)?.flag ?? null);

const nameMenu = ref(false);

/** Loaded when the dialog first opens to create a provider. */
const suggestions = ref<LlmProviderSuggestionDto[]>([]);

const loadSuggestions = async () => {
  if (suggestions.value.length > 0) {
    return;
  }
  try {
    suggestions.value = await getLlmProviderSuggestions();
  } catch {
    // Only a convenience: without them, all fields are entered by hand.
  }
};

/** Only offered when creating a provider, since choosing one fills in the other fields. */
const nameSuggestions = computed(() => current.value ? [] : suggestions.value);

/** The brand of the provider's own models, or for routers that requests may run anywhere; hosts have none. */
const suggestionSubtitle = (suggestion: LlmProviderSuggestionDto): {icon?: string, text: string} | null => {
  if (suggestion.model_brand) {
    return {text: suggestion.model_brand};
  }
  return suggestion.runs_inference ? null : {icon: 'mdi-call-split', text: t('admin.llm.providerDialog.thirdParty')};
};

const onNameFocused = (focused: boolean) => {
  if (focused && nameSuggestions.value.length > 0) {
    nameMenu.value = true;
  }
};

/** Fills in the other fields when the name is one of the suggestions. */
const onNameChange = (value: string | null) => {
  name.value = value ?? '';
  const suggestion = nameSuggestions.value.find(s => s.name === value);
  if (!suggestion) {
    return;
  }
  apiFormat.value = suggestion.api_format;
  // Like `load`, the official API is left to the placeholder.
  baseUrl.value = suggestion.base_url === DEFAULT_BASE_URLS[suggestion.api_format] ? '' : suggestion.base_url;
  currency.value = suggestion.currency;
};

const rules = {
  name: (value: string | null) => {
    const length = (value ?? '').trim().length;
    return (length > 0 && length <= MAX_NAME_LENGTH) || t('admin.llm.providerDialog.nameLength', {max: MAX_NAME_LENGTH});
  },
};

const currentKeyText = computed(() => {
  const key = current.value?.api_key;
  if (!key) {
    return t('admin.llm.providerDialog.keyNone');
  }
  return key.hint ? `•••• ${key.hint}` : t('admin.llm.providerDialog.keySet');
});

const origin = (url: string): string | null => {
  try {
    return new URL(url).origin;
  } catch {
    return null;
  }
};

/** Like the API, which compares the origins of the old and new base URL before keeping a key. */
const hostChanged = computed(() => {
  if (!current.value) {
    return false;
  }
  const effective = trimmedOrNull(baseUrl.value) ?? DEFAULT_BASE_URLS[apiFormat.value];
  const next = origin(effective);
  return next !== null && next !== origin(current.value.base_url);
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

  let change: ApiKeyChange;
  const key = trimmedOrNull(apiKey.value);
  if (!current.value) {
    change = key ? {action: 'SET', value: key} : {action: 'REMOVE'};
  } else if (keyAction.value === 'SET') {
    if (!key) {
      showSnackbar(t('admin.llm.providerDialog.missingApiKey'));
      return;
    }
    change = {action: 'SET', value: key};
  } else {
    change = {action: keyAction.value};
  }

  emit('submit', {
    name: trimmedName,
    api_format: apiFormat.value,
    base_url: trimmedOrNull(baseUrl.value),
    api_key: change,
    currency: currency.value || null,
  });
}

defineExpose({
  reset: () => {
    current.value = null;
    name.value = '';
    apiFormat.value = LlmApiFormat.OPENAI;
    baseUrl.value = '';
    keyAction.value = 'SET';
    apiKey.value = '';
    showKey.value = false;
    currency.value = DEFAULT_CURRENCY;
    loadSuggestions();
  },
  load: (provider: LlmProviderDto) => {
    current.value = provider;
    name.value = provider.name;
    apiFormat.value = provider.api_format;
    // The official API is shown as the placeholder, so switching the format follows it.
    baseUrl.value = provider.base_url === DEFAULT_BASE_URLS[provider.api_format] ? '' : provider.base_url;
    keyAction.value = provider.api_key ? 'KEEP' : 'REMOVE';
    apiKey.value = '';
    showKey.value = false;
    currency.value = provider.currency;
  },
});
</script>
