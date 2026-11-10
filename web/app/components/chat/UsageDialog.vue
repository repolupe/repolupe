<template>
  <v-dialog v-model="dialog" max-width="480">
    <!-- keyed, so the numbers jump rather than count when another message's usage is shown -->
    <v-card v-if="message?.usage" :key="message.id">
      <v-card-title class="d-flex align-center pt-4">
        <span class="flex-grow-1">{{ $t('chat.usageDialog.title') }}</span>
        <!-- stored once the answer is finished -->
        <v-btn v-if="message.status !== MessageStatus.GENERATING" variant="text" size="small" class="ml-2"
               prepend-icon="mdi-code-json" :text="$t('chat.usageDialog.raw')" :title="$t('chat.usageDialog.showRaw')"
               @click="emit('open-raw', message)"/>
      </v-card-title>
      <v-card-subtitle v-if="message.model_name" class="pb-2">
        <IconText icon="mdi-robot-outline">{{ message.model_name }}</IconText>
      </v-card-subtitle>

      <v-card-text>
        <v-table density="compact">
          <thead>
          <tr>
            <th>{{ $t('chat.usageDialog.type') }}</th>
            <th class="text-right">{{ $t('chat.usageDialog.tokens') }}</th>
            <th v-if="prices" class="text-right">{{ $t('chat.usageDialog.cost') }}</th>
          </tr>
          </thead>
          <tbody>
          <tr v-for="row in rows" :key="row.label">
            <td>
              {{ row.label }}
              <div class="text-caption text-medium-emphasis">{{ row.hint }}</div>
            </td>
            <td class="text-right tabular"><AnimatedNumber :value="row.tokens" :format="formatCount"/></td>
            <td v-if="row.cost" class="text-right tabular">
              <AnimatedNumber :value="Number(row.cost.amount)" :format="row.cost.format"/>
              <div class="text-caption text-medium-emphasis">
                {{ $t('chat.usageDialog.pricePerMillion', {price: row.cost.price}) }}
              </div>
            </td>
          </tr>
          </tbody>
          <tfoot>
          <tr class="font-weight-medium">
            <td>{{ $t('chat.usageDialog.total') }}</td>
            <td class="text-right tabular"><AnimatedNumber :value="total" :format="formatCount"/></td>
            <td v-if="prices && message.cost" class="text-right tabular">
              <AnimatedNumber :value="Number(message.cost.amount)" :format="formatCostAt(message.cost.amount)"/>
            </td>
          </tr>
          </tfoot>
        </v-table>
      </v-card-text>

      <v-card-actions>
        <v-spacer/>
        <v-btn :text="$t('common.close')" @click="dialog = false"/>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {useI18n} from "#i18n";
import {MessageStatus, type MessageDto} from "~/utils/model";
import {formatExactCost, formatPrice, tokenCost, totalTokens} from "~/utils/utils";
import {formatLocale} from "~/utils/i18n";
import IconText from "~/components/IconText.vue";
import AnimatedNumber from "~/components/AnimatedNumber.vue";

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'open-raw', message: MessageDto): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const message = ref<MessageDto | null>(null);

/** What the tokens were charged at, `null` without a cost or if unknown. */
const prices = computed(() => message.value?.cost?.prices ?? null);

const rows = computed(() => {
  const usage = message.value?.usage;
  if (!usage) {
    return [];
  }
  const currency = message.value?.cost?.currency ?? '';
  /** Of `tokens` at `price`, `null` without prices. */
  const cost = (tokens: number, price: string | undefined) => {
    if (price === undefined) {
      return null;
    }
    const amount = tokenCost(tokens, price);
    return {amount, format: formatCostAt(amount), price: formatPrice(price, currency)};
  };
  return [
    {label: t('common.input'), hint: t('chat.usageDialog.inputHint'), tokens: usage.input_tokens,
      cost: cost(usage.input_tokens, prices.value?.input)},
    {label: t('chat.usageDialog.cacheRead'), hint: t('chat.usageDialog.cacheReadHint'), tokens: usage.cache_read_tokens,
      cost: cost(usage.cache_read_tokens, prices.value?.cache_read)},
    {label: t('chat.usageDialog.cacheWrite'), hint: t('chat.usageDialog.cacheWriteHint'),
      tokens: usage.cache_write_tokens, cost: cost(usage.cache_write_tokens, prices.value?.cache_write)},
    {label: t('common.output'), hint: t('chat.usageDialog.outputHint'), tokens: usage.output_tokens,
      cost: cost(usage.output_tokens, prices.value?.output)},
  ];
});

const total = computed(() => message.value?.usage ? totalTokens(message.value.usage) : 0);

/** The numbers update while the answer is generating, and count up to the new ones. */
const formatCount = (value: number) => Math.round(value).toLocaleString(formatLocale());

/**
 * Formats the numbers counting to `amount` (in the currency of the cost) with as many decimals as it has, so the width
 * stays the same.
 */
const formatCostAt = (amount: string) => (value: number) => {
  const currency = message.value?.cost?.currency;
  if (!currency) {
    return '';
  }
  const decimals = amount.split('.')[1]?.length ?? 0;
  return formatExactCost(value === Number(amount) ? amount : value.toFixed(Math.min(decimals, 100)), currency);
};

defineExpose({
  load: (value: MessageDto) => {
    message.value = value;
  },
});
</script>

<style scoped>
.tabular {
  font-variant-numeric: tabular-nums;
}
</style>
