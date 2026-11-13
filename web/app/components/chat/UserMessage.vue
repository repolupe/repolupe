<template>
  <div class="user-message-row d-flex flex-column align-end ga-2">
    <!-- shown next to the chat if it can be, else downloaded -->
    <v-chip v-if="props.message.attachment" :href="previewable ? undefined : attachmentUrl(props.message.attachment.id)"
            size="large" variant="tonal" color="primary" prepend-icon="mdi-paperclip" class="attachment-chip"
            :title="$t(previewable ? 'chat.userMessage.show' : 'chat.userMessage.download',
                {name: props.message.attachment.file_name})"
            @click="previewable && emit('open-attachment', props.message.attachment)">
      <span class="text-truncate">{{ props.message.attachment.file_name }}</span>
      <span class="text-medium-emphasis ml-2 text-no-wrap">{{ formatBytes(props.message.attachment.size) }}</span>
    </v-chip>
    <div v-if="props.message.content.trim()" class="user-message bg-user-message"
         :title="formatDateTime(props.message.created_at)">{{ props.message.content }}</div>

    <!-- In the space below the message, so showing them moves nothing -->
    <div v-if="props.canResend" class="actions d-flex text-medium-emphasis">
      <v-btn icon="mdi-pencil-outline" variant="text" size="x-small" density="comfortable"
             :aria-label="$t('common.edit')" :title="$t('common.edit')" @click="emit('edit')"/>
      <v-btn icon="mdi-refresh" variant="text" size="x-small" density="comfortable"
             :aria-label="$t('common.retry')" :title="$t('common.retry')" @click="emit('retry')"/>
    </div>
  </div>
</template>

<script setup lang="ts">
import {computed} from "vue";
import type {AttachmentDto, MessageDto} from "~/utils/model";
import {attachmentUrl} from "~/utils/api";
import {attachmentPreviewKind, formatBytes, formatDateTime} from "~/utils/utils";

const props = defineProps<{
  message: MessageDto,
  /** Whether the message can be sent again, with or without a new text: not while an answer is generated. */
  canResend: boolean,
}>();

const emit = defineEmits<{
  (e: 'edit'): void,
  (e: 'retry'): void,
  (e: 'open-attachment', attachment: AttachmentDto): void,
}>();

const previewable = computed(() => !!props.message.attachment && attachmentPreviewKind(props.message.attachment) !== null);
</script>

<style scoped>
.user-message-row {
  position: relative;
}

.user-message {
  max-width: 85%;
  padding: 10px 16px;
  border-radius: 18px 18px 4px 18px;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  line-height: 1.5;
}

.attachment-chip {
  max-width: 85%;
}

.actions {
  position: absolute;
  top: 100%;
  right: 0;
  opacity: 0;
  transition: opacity 150ms;
}

.user-message-row:hover .actions, .actions:focus-within {
  opacity: 1;
}

/* nothing to hover with, e.g. on a phone */
@media (hover: none) {
  .actions {
    opacity: 1;
  }
}
</style>
