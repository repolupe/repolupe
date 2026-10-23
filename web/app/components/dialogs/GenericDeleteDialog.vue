<template>
  <v-dialog v-model="dialog" width="auto">
    <v-card width="500" :title="props.title">
      <template v-slot:text>
        <slot></slot>
        <br>
        <div v-show="verify">
          {{ $t('app.genericDeleteDialog.verifyPrompt', {verify}) }}
          <br><br>
          <v-text-field ref="userVerifyTextField" v-model="userVerifyInput" @keydown.enter="onDelete"
                        :label="$t('app.genericDeleteDialog.verification')" :rules="[rules.required, rules.check]"
                        :disabled="loading"/>
        </div>
      </template>

      <template v-slot:actions>
        <v-btn :text="$t('common.cancel')" @click="dialog = false"/>

        <v-btn @click="onDelete" color="primary" variant="elevated" :loading="loading"
               prepend-icon="mdi-delete" :text="$t('common.delete')" />
      </template>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed, ref, watch} from "vue";
import {useI18n} from "#i18n";

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  title: string,
  verify?: string,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'delete'): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const userVerifyInput = ref('');

// The dialog is reused for different items, so start every opening with an empty field.
watch(() => props.modelValue, (open) => {
  if (open) {
    userVerifyInput.value = '';
  }
});
const rules = {
  required: (value: string) => !!value || t('common.required'),
  check: (value: string) => value === props.verify || t('app.genericDeleteDialog.mismatch')
};

const onDelete = () => {
  if (props.verify && props.verify !== userVerifyInput.value) {
    return;
  }
  emit('delete');
}
</script>
