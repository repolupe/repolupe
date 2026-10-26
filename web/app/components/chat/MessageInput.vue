<template>
  <div>
    <div v-if="props.attachment" class="mb-2">
      <v-chip size="large" variant="flat" color="surface" closable :disabled="props.disabled"
              :title="props.attachment.file_name" class="attachment-chip" @click:close="emit('update:attachment', null)">
        <template v-slot:prepend>
          <v-progress-circular v-if="!props.attachment.uploaded" indeterminate size="18" width="2" class="mr-2"/>
          <v-icon v-else icon="mdi-paperclip" class="mr-2"/>
        </template>
        <span class="text-truncate">{{ props.attachment.file_name }}</span>
        <span class="text-medium-emphasis ml-2 text-no-wrap">{{ formatBytes(props.attachment.size) }}</span>
      </v-chip>
    </div>

    <v-textarea ref="textarea" v-model="content" class="message-input" :placeholder="props.placeholder" rows="1" max-rows="8"
                auto-grow variant="solo" bg-color="surface" rounded="lg" hide-details autofocus
                :maxlength="MAX_LENGTH" :disabled="props.disabled" @keydown.enter="onEnter">
      <template v-slot:append-inner>
        <v-btn v-if="props.generating" icon="mdi-stop" color="primary" variant="tonal"
               :loading="props.stopping" :aria-label="$t('chat.messageInput.stop')" :title="$t('chat.messageInput.stop')" @click="emit('stop')"/>
        <v-btn v-else icon="mdi-send" color="primary" variant="plain" :disabled="!props.canSend"
               :loading="props.sending" :aria-label="$t('chat.messageInput.send')" :title="$t('chat.messageInput.send')" @click="emit('send')"/>
      </template>
    </v-textarea>

    <Teleport to="body">
      <div v-if="dragging" class="drop-overlay">
        <div class="drop-hint text-h6">
          <v-icon icon="mdi-paperclip" class="mr-2"/>
          {{ $t('chat.messageInput.dropHint') }}
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, onMounted, ref, useTemplateRef} from "vue";
import {useI18n} from "#i18n";
import {errorMessage, MAX_ATTACHMENT_BYTES, uploadAttachment} from "~/utils/api";
import {formatBytes, showSnackbar, type PendingAttachment} from "~/utils/utils";

/** Same as the API's limit. */
const MAX_LENGTH = 32000;

const props = defineProps<{
  modelValue: string,
  placeholder: string,
  canSend: boolean,
  sending?: boolean,
  disabled?: boolean,
  /** Shows a stop button instead of the send button. */
  generating?: boolean,
  stopping?: boolean,
  /** The file dropped anywhere on the page, uploaded right away to be sent with the message. */
  attachment?: PendingAttachment | null,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void,
  (e: 'update:attachment', value: PendingAttachment | null): void,
  (e: 'send'): void,
  (e: 'stop'): void,
}>();

const {t} = useI18n();

const textarea = useTemplateRef<HTMLTextAreaElement>('textarea');

/** Whether files are dragged over the page. */
const dragging = ref(false);
/** `dragenter` and `dragleave` fire for every element passed, so the page is left when they even out. */
let dragDepth = 0;
let nextKey = 1;

const content = computed({
  get: () => props.modelValue,
  set: (val: string) => emit('update:modelValue', val),
});

/** Enter sends, Shift+Enter inserts a new line. */
const onEnter = (e: KeyboardEvent) => {
  if (e.shiftKey || e.isComposing) {
    return;
  }
  e.preventDefault();
  emit('send');
};

const attach = async (file: File) => {
  if (file.size > MAX_ATTACHMENT_BYTES) {
    showSnackbar(t('chat.messageInput.fileTooLarge', {max: formatBytes(MAX_ATTACHMENT_BYTES)}));
    return;
  }
  const key = nextKey++;
  const pending: PendingAttachment = {key, file_name: file.name, size: file.size, uploaded: null};
  emit('update:attachment', pending);
  try {
    const uploaded = await uploadAttachment(file);
    // removed or replaced in the meantime
    if (props.attachment?.key === key) {
      emit('update:attachment', {...pending, uploaded});
    }
  } catch (e) {
    if (props.attachment?.key === key) {
      emit('update:attachment', null);
    }
    showSnackbar(t('chat.messageInput.uploadFailed', {error: errorMessage(e)}));
  }
};

const hasFiles = (e: DragEvent) => e.dataTransfer?.types.includes('Files') ?? false;

const onDragEnter = (e: DragEvent) => {
  if (!hasFiles(e)) {
    return;
  }
  e.preventDefault();
  dragDepth++;
  dragging.value = !props.disabled;
};

const onDragOver = (e: DragEvent) => {
  if (!hasFiles(e)) {
    return;
  }
  // otherwise the browser opens the file instead of dropping it here
  e.preventDefault();
  e.dataTransfer!.dropEffect = props.disabled ? 'none' : 'copy';
};

const onDragLeave = (e: DragEvent) => {
  if (!hasFiles(e)) {
    return;
  }
  dragDepth = Math.max(0, dragDepth - 1);
  if (dragDepth === 0) {
    dragging.value = false;
  }
};

const onDrop = (e: DragEvent) => {
  if (!hasFiles(e)) {
    return;
  }
  e.preventDefault();
  dragDepth = 0;
  dragging.value = false;
  const files = [...e.dataTransfer!.files];
  if (props.disabled || files.length === 0) {
    return;
  }
  if (files.length > 1) {
    showSnackbar(t('chat.messageInput.oneFileOnly'));
    return;
  }
  attach(files[0]!);
};

onMounted(() => {
  window.addEventListener('dragenter', onDragEnter);
  window.addEventListener('dragover', onDragOver);
  window.addEventListener('dragleave', onDragLeave);
  window.addEventListener('drop', onDrop);
});

onBeforeUnmount(() => {
  window.removeEventListener('dragenter', onDragEnter);
  window.removeEventListener('dragover', onDragOver);
  window.removeEventListener('dragleave', onDragLeave);
  window.removeEventListener('drop', onDrop);
});

defineExpose({
  focus: () => textarea.value?.focus(),
});
</script>

<style scoped>
.message-input {
  /* moves from the middle of the new chat page to the bottom of the chat page */
  view-transition-name: message-input;
}

.message-input :deep(.v-field__append-inner) {
  /* centers the 48px button in the 56px single-line field and keeps it at the bottom as the field grows */
  align-self: flex-end;
  padding-top: 0;
  padding-bottom: 4px;
}

.attachment-chip {
  max-width: 100%;
}

.drop-overlay {
  position: fixed;
  inset: 0;
  z-index: 2000;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(var(--v-theme-primary), 0.12);
  border: 3px dashed rgb(var(--v-theme-primary));
  /* the drag events go to the page below */
  pointer-events: none;
}

.drop-hint {
  display: flex;
  align-items: center;
  padding: 16px 24px;
  border-radius: 12px;
  background: rgb(var(--v-theme-surface));
  color: rgb(var(--v-theme-primary));
}
</style>

<style>
/* not scoped: the pseudo-elements live on the document root */
::view-transition-group(message-input) {
  animation-duration: 350ms;
  animation-timing-function: cubic-bezier(0.2, 0, 0, 1);
}
</style>
