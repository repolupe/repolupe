<template>
  <GenericSaveDialog v-model="dialog" :loading="props.loading" :title="$t('chat.editMessageDialog.title')"
                     :submit-text="$t('chat.messageInput.send')" submit-icon="mdi-send" @submit="submit">
    <v-form ref="form" @submit.prevent="submit">
      <v-textarea v-model="content" :label="$t('chat.placeholder')" rows="3" max-rows="12" auto-grow autofocus
                  :maxlength="MAX_LENGTH" :disabled="props.loading" :rules="[rules.required]"
                  @keydown.enter="onEnter"/>
    </v-form>
    <p v-if="props.removesLater" class="text-body-2 text-medium-emphasis">
      {{ $t('chat.editMessageDialog.removesLater') }}
    </p>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref, useTemplateRef} from "vue";
import {useI18n} from "#i18n";
import type {MessageDto} from "~/utils/model";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

/** Same as the API's limit. */
const MAX_LENGTH = 32000;

const {t} = useI18n();

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  /** Whether sending it removes more than its answer. */
  removesLater: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', content: string): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const form = useTemplateRef<{ validate: () => Promise<{ valid: boolean }> }>('form');

const content = ref('');
/** A message with an attachment needs no text. */
const hasAttachment = ref(false);

const rules = {
  required: (value: string) => hasAttachment.value || !!value.trim() || t('common.required'),
};

defineExpose({
  load: (message: MessageDto) => {
    content.value = message.content;
    hasAttachment.value = !!message.attachment;
  },
});

/** Enter starts a new line, as the message is usually longer than one. */
const onEnter = (e: KeyboardEvent) => {
  if (e.ctrlKey || e.metaKey) {
    e.preventDefault();
    submit();
  }
};

const submit = async () => {
  const {valid} = await form.value!.validate();
  if (!valid) {
    return;
  }
  emit('submit', content.value);
};
</script>
