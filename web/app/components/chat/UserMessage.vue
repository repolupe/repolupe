<template>
  <div class="d-flex flex-column align-end ga-2">
    <v-chip v-if="props.message.attachment" :href="attachmentUrl(props.message.attachment.id)" size="large"
            variant="tonal" color="primary" prepend-icon="mdi-paperclip" class="attachment-chip"
            :title="$t('chat.userMessage.download', {name: props.message.attachment.file_name})">
      <span class="text-truncate">{{ props.message.attachment.file_name }}</span>
      <span class="text-medium-emphasis ml-2 text-no-wrap">{{ formatBytes(props.message.attachment.size) }}</span>
    </v-chip>
    <div v-if="props.message.content.trim()" class="user-message bg-primary"
         :title="formatDateTime(props.message.created_at)">{{ props.message.content }}</div>
  </div>
</template>

<script setup lang="ts">
import type {MessageDto} from "~/utils/model";
import {attachmentUrl} from "~/utils/api";
import {formatBytes, formatDateTime} from "~/utils/utils";

const props = defineProps<{
  message: MessageDto,
}>();
</script>

<style scoped>
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
</style>
