<template>
  <v-dialog v-model="dialog" max-width="480">
    <!-- keyed, so the numbers jump rather than count when another message's usage is shown -->
    <v-card v-if="message?.usage" :key="message.id">
      <v-card-title class="pt-4">{{ $t('chat.usageDialog.title') }}</v-card-title>
      <v-card-subtitle v-if="modelName" class="pb-2">
        <IconText icon="mdi-robot-outline">{{ modelName }}</IconText>
      </v-card-subtitle>

      <v-card-text>
        <v-table density="compact">
          <thead>
          <tr>
            <th>{{ $t('chat.usageDialog.type') }}</th>
            <th class="text-right">{{ $t('chat.usageDialog.tokens') }}</th>
          </tr>
          </thead>
          <tbody>
          <tr v-for="row in rows" :key="row.label">
            <td>
              {{ row.label }}
              <div class="text-caption text-medium-emphasis">{{ row.hint }}</div>
            </td>
            <td class="text-right tabular"><AnimatedNumber :value="row.tokens" :format="formatCount"/></td>
          </tr>
          </tbody>
          <tfoot>
          <tr class="font-weight-medium">
            <td>{{ $t('chat.usageDialog.total') }}</td>
            <td class="text-right tabular"><AnimatedNumber :value="total" :format="formatCount"/></td>
          </tr>
          <tr v-if="message.cost" class="font-weight-medium">
            <td>{{ $t('chat.usageDialog.cost') }}</td>
            <td class="text-right tabular"><AnimatedNumber :value="Number(message.cost.amount)" :format="formatCostAt"/></td>
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
import type {MessageDto} from "~/utils/model";
import {formatExactCost, totalTokens} from "~/utils/utils";
import {formatLocale} from "~/utils/i18n";
import IconText from "~/components/IconText.vue";
import AnimatedNumber from "~/components/AnimatedNumber.vue";

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const message = ref<MessageDto | null>(null);
const modelName = ref<string | null>(null);

const rows = computed(() => {
  const usage = message.value?.usage;
  if (!usage) {
    return [];
  }
  return [
    {label: t('common.input'), hint: t('chat.usageDialog.inputHint'), tokens: usage.input_tokens},
    {label: t('chat.usageDialog.cacheRead'), hint: t('chat.usageDialog.cacheReadHint'), tokens: usage.cache_read_tokens},
    {label: t('chat.usageDialog.cacheWrite'), hint: t('chat.usageDialog.cacheWriteHint'), tokens: usage.cache_write_tokens},
    {label: t('common.output'), hint: t('chat.usageDialog.outputHint'), tokens: usage.output_tokens},
  ];
});

const total = computed(() => message.value?.usage ? totalTokens(message.value.usage) : 0);

/** The numbers update while the answer is generating, and count up to the new ones. */
const formatCount = (value: number) => Math.round(value).toLocaleString(formatLocale());

/** With as many decimals while counting as the cost has, so the width stays the same. */
const formatCostAt = (value: number) => {
  const cost = message.value?.cost;
  if (!cost) {
    return '';
  }
  const decimals = cost.amount.split('.')[1]?.length ?? 0;
  const amount = value === Number(cost.amount) ? cost.amount : value.toFixed(Math.min(decimals, 100));
  return formatExactCost(amount, cost.currency);
};

defineExpose({
  load: (value: MessageDto, name: string | null) => {
    message.value = value;
    modelName.value = name;
  },
});
</script>

<style scoped>
.tabular {
  font-variant-numeric: tabular-nums;
}
</style>
