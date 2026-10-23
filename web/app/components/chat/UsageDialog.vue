<template>
  <v-dialog v-model="dialog" max-width="480">
    <v-card v-if="message?.usage">
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
            <td class="text-right tabular">{{ row.tokens.toLocaleString(formatLocale()) }}</td>
          </tr>
          </tbody>
          <tfoot>
          <tr class="font-weight-medium">
            <td>{{ $t('chat.usageDialog.total') }}</td>
            <td class="text-right tabular">{{ total.toLocaleString(formatLocale()) }}</td>
          </tr>
          <tr v-if="message.cost" class="font-weight-medium">
            <td>{{ $t('chat.usageDialog.cost') }}</td>
            <td class="text-right tabular">{{ formatExactCost(message.cost.amount, message.cost.currency) }}</td>
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
import {formatExactCost} from "~/utils/utils";
import {formatLocale} from "~/utils/i18n";
import IconText from "~/components/IconText.vue";

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

const total = computed(() => rows.value.reduce((sum, row) => sum + row.tokens, 0));

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
