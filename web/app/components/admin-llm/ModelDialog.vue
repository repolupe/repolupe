<template>
  <GenericSaveDialog :title="editing ? $t('admin.llm.modelDialog.editTitle') : $t('admin.llm.modelDialog.newTitle', {provider: props.providerName})" v-model="dialog"
                     :loading="props.loading" @submit="submit">
    <v-text-field v-model="apiName" @keydown.enter="submit" :label="`${$t('admin.llm.modelDialog.apiName')}*`" placeholder="claude-opus-5-5"
                  prepend-icon="mdi-robot" class="mb-2" :disabled="loading" :counter="MAX_API_NAME_LENGTH" />

    <v-text-field v-model="displayName" @keydown.enter="submit" :label="$t('admin.llm.modelDialog.displayName')"
                  :placeholder="apiName.trim() || 'Claude Opus 5.5'" persistent-placeholder
                  prepend-icon="mdi-label" class="mt-2 mb-2" :disabled="loading" :counter="MAX_DISPLAY_NAME_LENGTH" />

    <v-text-field v-model="maxOutputTokens" @keydown.enter="submit" :label="$t('admin.llm.modelDialog.maxOutputTokens')"
                  type="number" min="1" step="1" prepend-icon="mdi-counter" class="mt-2" :disabled="loading"
                  :rules="[rules.tokens]" />

    <div class="d-flex align-center mt-6">
      <v-icon class="mr-4 text-medium-emphasis">mdi-cash</v-icon>
      <span class="text-body-1">{{ $t('admin.llm.pricePerMillion') }}</span>
    </div>
    <p v-if="!props.currency" class="text-caption text-medium-emphasis ml-10 mb-2">
      {{ $t('admin.llm.modelDialog.noCurrency') }}
    </p>
    <p v-else class="text-caption text-medium-emphasis ml-10 mb-2">
      {{ $t('admin.llm.modelDialog.priceHint') }}
    </p>
    <v-row v-if="props.currency" dense class="ml-8">
      <v-col cols="6">
        <v-text-field v-model="inputPrice" @keydown.enter="submit" :label="$t('common.input')" inputmode="decimal"
                      :suffix="props.currency" :disabled="loading" :rules="[rules.price]" />
      </v-col>
      <v-col cols="6">
        <v-text-field v-model="outputPrice" @keydown.enter="submit" :label="$t('common.output')" inputmode="decimal"
                      :suffix="props.currency" :disabled="loading" :rules="[rules.price]" />
      </v-col>
      <v-col cols="6">
        <v-text-field v-model="cacheReadPrice" @keydown.enter="submit" :label="$t('admin.llm.modelDialog.cacheRead')" inputmode="decimal"
                      :suffix="props.currency" :placeholder="$t('admin.llm.modelDialog.sameAsInput')" persistent-placeholder
                      :disabled="loading" :rules="[rules.price]" />
      </v-col>
      <v-col cols="6">
        <v-text-field v-model="cacheWritePrice" @keydown.enter="submit" :label="$t('admin.llm.modelDialog.cacheWrite')" inputmode="decimal"
                      :suffix="props.currency" :placeholder="$t('admin.llm.modelDialog.sameAsInput')" persistent-placeholder
                      :disabled="loading" :rules="[rules.price]" />
      </v-col>
    </v-row>

    <v-alert v-if="!editing && props.becomesDefault" type="info" variant="tonal" density="compact" class="mt-4">
      {{ $t('admin.llm.modelDialog.becomesDefault') }}
    </v-alert>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {charCount, showSnackbar} from "~/utils/utils";
import {formatLocale} from "~/utils/i18n";
import type {LlmModelPayload} from "~/utils/api";
import type {LlmModelDto} from "~/utils/model";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";
import {useI18n} from "#i18n";

const MAX_DISPLAY_NAME_LENGTH = 100;
const MAX_API_NAME_LENGTH = 200;
/** `max_output_tokens` is an `i32` in the API. */
const MAX_TOKENS = 2_147_483_647;
/** Mirrors the API's limits on prices per million tokens. */
const MAX_PRICE = 100_000;
const MAX_PRICE_DECIMALS = 6;
const PRICE_PATTERN = new RegExp(`^\\d+(\\.\\d{1,${MAX_PRICE_DECIMALS}})?$`);

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  providerName: string,
  /** The provider's currency, which the prices are in. `null` if its models have no prices. */
  currency: string | null,
  /** Whether a newly created model becomes the default, i.e. there is none yet. */
  becomesDefault: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', value: LlmModelPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const editing = ref(false);
const displayName = ref('');
const apiName = ref('');
// v-text-field with type="number" may give a number or a string
const maxOutputTokens = ref<string | number>('');
const inputPrice = ref('');
const outputPrice = ref('');
const cacheReadPrice = ref('');
const cacheWritePrice = ref('');

/** `null` for empty, `undefined` for invalid input. */
const parseTokens = (value: string | number): number | null | undefined => {
  const text = String(value ?? '').trim();
  if (!text) {
    return null;
  }
  const tokens = Number(text);
  if (!Number.isInteger(tokens) || tokens <= 0 || tokens > MAX_TOKENS) {
    return undefined;
  }
  return tokens;
};

/** A decimal string for the API, `null` for empty, `undefined` for invalid input. Accepts a decimal comma. */
const parsePrice = (value: string): string | null | undefined => {
  const text = (value ?? '').trim().replace(',', '.');
  if (!text) {
    return null;
  }
  if (!PRICE_PATTERN.test(text) || Number(text) > MAX_PRICE) {
    return undefined;
  }
  return text;
};

const rules = {
  tokens: (value: string | number) => parseTokens(value) !== undefined || t('admin.llm.modelDialog.tokensInvalid'),
  price: (value: string) => parsePrice(value) !== undefined
      || t('admin.llm.modelDialog.priceInvalid', {max: MAX_PRICE.toLocaleString(formatLocale()), decimals: MAX_PRICE_DECIMALS}),
};

const submit = () => {
  const trimmedApiName = apiName.value.trim();
  if (!trimmedApiName) {
    showSnackbar(t('admin.llm.modelDialog.missingApiName'));
    return;
  }
  if (charCount(trimmedApiName) > MAX_API_NAME_LENGTH) {
    showSnackbar(t('admin.llm.modelDialog.apiNameTooLong', {max: MAX_API_NAME_LENGTH}));
    return;
  }

  const trimmedDisplayName = displayName.value.trim();
  if (charCount(trimmedDisplayName) > MAX_DISPLAY_NAME_LENGTH) {
    showSnackbar(t('admin.llm.modelDialog.displayNameTooLong', {max: MAX_DISPLAY_NAME_LENGTH}));
    return;
  }

  const tokens = parseTokens(maxOutputTokens.value);
  if (tokens === undefined) {
    showSnackbar(t('admin.llm.modelDialog.maxOutputTokensInvalid'));
    return;
  }

  // without a currency, the price fields are hidden
  const prices = props.currency
      ? [inputPrice, outputPrice, cacheReadPrice, cacheWritePrice].map(p => parsePrice(p.value))
      : [null, null, null, null];
  if (prices.includes(undefined)) {
    showSnackbar(t('admin.llm.modelDialog.pricesInvalid', {max: MAX_PRICE.toLocaleString(formatLocale()), decimals: MAX_PRICE_DECIMALS}));
    return;
  }
  const [input, output, cacheRead, cacheWrite] = prices as (string | null)[];
  if ((input === null) !== (output === null)) {
    showSnackbar(t('admin.llm.modelDialog.inputOutputBoth'));
    return;
  }
  if (input === null && (cacheRead !== null || cacheWrite !== null)) {
    showSnackbar(t('admin.llm.modelDialog.cacheRequiresPrices'));
    return;
  }

  emit('submit', {
    api_name: trimmedApiName,
    display_name: trimmedDisplayName || null,
    max_output_tokens: tokens,
    input_price: input ?? null,
    output_price: output ?? null,
    cache_read_price: cacheRead ?? null,
    cache_write_price: cacheWrite ?? null,
  });
}

defineExpose({
  reset: () => {
    editing.value = false;
    displayName.value = '';
    apiName.value = '';
    maxOutputTokens.value = '';
    inputPrice.value = '';
    outputPrice.value = '';
    cacheReadPrice.value = '';
    cacheWritePrice.value = '';
  },
  load: (model: LlmModelDto) => {
    editing.value = true;
    displayName.value = model.display_name ?? '';
    apiName.value = model.api_name;
    maxOutputTokens.value = model.max_output_tokens ?? '';
    inputPrice.value = model.input_price ?? '';
    outputPrice.value = model.output_price ?? '';
    cacheReadPrice.value = model.cache_read_price ?? '';
    cacheWritePrice.value = model.cache_write_price ?? '';
  },
});
</script>
