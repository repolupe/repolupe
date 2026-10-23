<template>
  <div class="chat-layout">
    <div class="chat-page">
      <div ref="chat-body" class="chat-column chat-body">
        <!-- header -->
        <div v-if="chat" class="d-flex align-start mb-6">
          <div class="flex-grow-1" style="min-width: 0">
            <div class="d-flex align-baseline flex-wrap" style="column-gap: 12px">
              <h1 class="text-h6 chat-title">{{ chat.title }}</h1>
              <IconText v-if="chat.all_repositories || chat.repository_ids.length > 0" icon="mdi-folder"
                        class="text-body-2 text-medium-emphasis">
                {{ repositoryScopeSummary(chat, repositories) }}
              </IconText>
            </div>
            <IconText v-if="chat.temporary" icon="mdi-progress-clock" class="text-body-2 text-medium-emphasis mt-1">
              {{ $t('chat.temporary') }}
            </IconText>
          </div>

          <!-- a temporary chat is neither renamed nor deleted, it is deleted on its own -->
          <v-menu v-if="!chat.temporary" location="bottom end">
            <template v-slot:activator="{ props: menuProps }">
              <v-btn v-bind="menuProps" icon="mdi-dots-vertical" variant="text" :aria-label="$t('chat.page.actions')"/>
            </template>
            <v-list density="compact">
              <v-list-item prepend-icon="mdi-pencil" :title="$t('chat.page.rename')" @click="showRenameDialog"/>
              <v-list-item prepend-icon="mdi-delete" :title="$t('common.delete')" @click="dialogDelete = true"/>
            </v-list>
          </v-menu>
        </div>

        <div v-if="fetching && !chat" class="d-flex justify-center mt-16">
          <v-progress-circular indeterminate color="primary"/>
        </div>

        <!-- messages -->
        <div v-if="chat" class="d-flex flex-column ga-4">
          <template v-for="message in chat.messages" :key="message.id">
            <UserMessage v-if="message.role === MessageRole.USER" :message="message"/>
            <AssistantMessage v-else :message="message" :model-name="modelNames.get(message.model_id ?? '')"
                              :can-retry="message.id === retryableId"
                              :retrying="retryingId === message.id" @retry="doRetry(message)"
                              @open-tool-call="showToolCallDialog"
                              @open-file="(t) => presentedFile = t"
                              @open-usage="showUsageDialog(message)"/>
          </template>
        </div>
      </div>

      <!-- composer -->
      <div class="composer">
        <div class="chat-column">
          <MessageInput ref="message-input" v-model="input" v-model:attachment="attachment"
                        :placeholder="$t('chat.placeholder')" :can-send="canSend"
                        :sending="sending" :generating="!!generatingMessage" :stopping="stopping"
                        @send="doSend" @stop="doStop"/>
          <!-- hidden but taking its space while loading, so the input does not jump up after the view transition -->
          <div v-if="!modelsLoaded || models.length > 0" class="mt-4 d-flex align-center"
               :style="{visibility: chat && modelsLoaded ? 'visible' : 'hidden'}">
            <ChatModelSelect :model-value="chat?.model_id ?? null" :models="models"
                             :disabled="!chat || loading" @update:model-value="doChangeModel"/>
          </div>
        </div>
      </div>

      <RenameChatDialog ref="rename-dialog" v-model="dialogRename" :loading="loading" @submit="doRename"/>

      <GenericDeleteDialog v-model="dialogDelete" :loading="loading" :title="$t('chat.page.deleteTitle')"
                           @delete="doDelete">
        {{ $t('chat.page.deleteConfirm', {title: chat?.title}) }}
      </GenericDeleteDialog>

      <ToolCallDialog v-if="chat" ref="tool-call-dialog" v-model="dialogToolCall"
                      :chat-id="chat.id" :repositories="repositories"/>

      <UsageDialog ref="usage-dialog" v-model="dialogUsage"/>
    </div>

    <Transition name="file-panel">
      <div v-if="chat && presentedFile" class="file-panel">
        <!-- stays while the panel is open, so switching to another kind of file does not fade in again -->
        <div class="file-panel-content">
          <ProposedCommitPanel v-if="CHANGE_TOOLS.includes(presentedFile.name)" class="file-panel-card"
                           :chat-id="chat.id" :tool-call="presentedFile" :repositories="repositories"
                           @close="presentedFile = null"/>
          <PresentedFilePanel v-else class="file-panel-card" :chat-id="chat.id" :tool-call="presentedFile"
                              :repositories="repositories" @close="presentedFile = null"/>
        </div>
      </div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import {computed, nextTick, onBeforeUnmount, onMounted, ref, useTemplateRef, watch} from "vue";
import {navigateTo, useHead, useRoute} from "#app";
import {useI18n} from "#i18n";
import {useDisplay} from "vuetify";
import {
  ErrorCode,
  MessageRole,
  MessageStatus,
  type ChatDetailDto,
  type MessageDto,
  type MessageStreamEvent,
  type ModelDto,
  type RepositoryDto,
  type ToolCallSummaryDto,
} from "~/utils/model";
import {
  ApiError,
  cancelMessage,
  deleteChat,
  errorMessage,
  getChat,
  getModels,
  getRepositories,
  retryMessage,
  sendMessage,
  streamMessage,
  updateChat,
} from "~/utils/api";
import {
  CHANGE_TOOLS,
  presentedFiles,
  proposedChanges,
  repositoryScopeSummary,
  showSnackbar,
  type PendingAttachment,
} from "~/utils/utils";
import {refreshChats, useFilePresented, useInstanceTitle, useUser} from "~/composables/states";
import GenericDeleteDialog from "~/components/dialogs/GenericDeleteDialog.vue";
import IconText from "~/components/IconText.vue";
import UserMessage from "~/components/chat/UserMessage.vue";
import AssistantMessage from "~/components/chat/AssistantMessage.vue";
import ToolCallDialog from "~/components/chat/ToolCallDialog.vue";
import PresentedFilePanel from "~/components/chat/panel/PresentedFilePanel.vue";
import ProposedCommitPanel from "~/components/chat/panel/ProposedCommitPanel.vue";
import UsageDialog from "~/components/chat/UsageDialog.vue";
import RenameChatDialog from "~/components/chat/RenameChatDialog.vue";
import MessageInput from "~/components/chat/MessageInput.vue";
import ChatModelSelect from "~/components/chat/ChatModelSelect.vue";

/** A stream that cannot be reopened this often in a row (without a snapshot in between) is given up. */
const MAX_STREAM_ERRORS = 3;
/** Distance from the bottom (px) within which new content keeps the page scrolled to the bottom. */
const STICK_THRESHOLD = 120;

const {t} = useI18n();
const route = useRoute();
const display = useDisplay();
const instanceTitle = useInstanceTitle();
const user = useUser();

const renameDialog = useTemplateRef<InstanceType<typeof RenameChatDialog>>('rename-dialog');
const toolCallDialog = useTemplateRef<InstanceType<typeof ToolCallDialog>>('tool-call-dialog');
const usageDialog = useTemplateRef<InstanceType<typeof UsageDialog>>('usage-dialog');
const messageInput = useTemplateRef<InstanceType<typeof MessageInput>>('message-input');
const chatBody = useTemplateRef<HTMLElement>('chat-body');

const chat = ref<ChatDetailDto | null>(null);
const repositories = ref<RepositoryDto[]>([]);
const models = ref<ModelDto[]>([]);
const modelsLoaded = ref(false);
const fetching = ref(false);
const loading = ref(false);

const input = ref('');
/** Sent with the next message once uploaded. */
const attachment = ref<PendingAttachment | null>(null);
const sending = ref(false);
const stopping = ref(false);
const retryingId = ref<string | null>(null);

const dialogRename = ref(false);
const dialogDelete = ref(false);
const dialogToolCall = ref(false);
const dialogUsage = ref(false);

/** The `present_file_to_user` call whose file, or the `change_file` or `save_attachment` call whose change, is shown next to the chat. */
const presentedFile = ref<ToolCallSummaryDto | null>(null);

const filePresented = useFilePresented();
watch(presentedFile, (file) => {
  filePresented.value = !!file;
});

/** The chat of the current route, set before it is loaded. */
let currentId: string | null = null;
let closeStream: (() => void) | null = null;
let streamingMessageId: string | null = null;
let streamErrors = 0;
let stickToBottom = true;

useHead({title: computed(() => chat.value ? `${chat.value.title} - ${instanceTitle.value}` : instanceTitle.value)});

const generatingMessage = computed(() => chat.value?.messages
    .find(m => m.role === MessageRole.ASSISTANT && m.status === MessageStatus.GENERATING) ?? null);

/** Only the last answer can be retried, and only if it failed or was cancelled. */
const retryableId = computed(() => {
  const last = chat.value?.messages.at(-1);
  if (!last || last.role !== MessageRole.ASSISTANT) {
    return null;
  }
  return last.status === MessageStatus.FAILED || last.status === MessageStatus.CANCELLED ? last.id : null;
});

const canSend = computed(() => !!chat.value && !sending.value && !generatingMessage.value
    && (attachment.value ? !!attachment.value.uploaded : !!input.value.trim()));

const modelNames = computed(() => new Map(models.value.map(m => [m.id, m.display_name])));

// --- scrolling ---

const isNearBottom = () => window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - STICK_THRESHOLD;

const onScroll = () => {
  stickToBottom = isNearBottom();
};

/** Follows the answer as it grows, also between stream events while its text is revealed. */
const bodyObserver = new ResizeObserver(() => {
  if (stickToBottom) {
    window.scrollTo({top: document.documentElement.scrollHeight});
  }
});

/** Scrolls to the bottom after the next render, unless the user scrolled up (or `force`). */
const scrollToBottom = async (force: boolean) => {
  if (!force && !stickToBottom) {
    return;
  }
  await nextTick();
  window.scrollTo({top: document.documentElement.scrollHeight});
  stickToBottom = true;
};

// --- streaming ---

const stopStream = () => {
  closeStream?.();
  closeStream = null;
  streamingMessageId = null;
};

const startStream = (chatId: string, messageId: string) => {
  stopStream();
  streamingMessageId = messageId;
  closeStream = streamMessage(chatId, messageId, (event) => {
    if (streamingMessageId !== messageId || chat.value?.id !== chatId) {
      return;
    }
    applyStreamEvent(messageId, event);
  }, () => {
    if (streamingMessageId !== messageId) {
      return;
    }
    closeStream = null;
    streamingMessageId = null;
    onStreamError(chatId);
  });
};

const applyStreamEvent = (messageId: string, event: MessageStreamEvent) => {
  const messages = chat.value!.messages;
  const index = messages.findIndex(m => m.id === messageId);
  if (index < 0) {
    return;
  }
  const message = messages[index]!;

  switch (event.type) {
    case 'snapshot':
      messages[index] = event.data;
      streamErrors = 0;
      break;
    case 'content_delta':
      message.content += event.data.text;
      break;
    case 'tool_call_started':
      if (!message.tool_calls.some(t => t.id === event.data.id)) {
        message.tool_calls.push(event.data);
      }
      break;
    case 'tool_call_finished': {
      const toolCall = message.tool_calls.find(t => t.id === event.data.id);
      if (toolCall) {
        toolCall.status = event.data.status;
      }
      break;
    }
    case 'done': {
      messages[index] = event.data;
      // an answer that proposes a single change, or else shows a single file, opens it right away,
      // except where the panel would cover the answer (below 960px, see the styles); changes the
      // server applied automatically need no review
      const files = presentedFiles(event.data);
      const changes = proposedChanges(event.data);
      const autoOpen = event.data.status === MessageStatus.COMPLETED && !display.smAndDown.value;
      if (autoOpen && changes.length === 1 && !user.value?.auto_commit) {
        presentedFile.value = changes[0]!.toolCall;
      } else if (autoOpen && changes.length === 0 && files.length === 1) {
        presentedFile.value = files[0]!.toolCall;
      }
      // the stream closes itself after `done`
      closeStream = null;
      streamingMessageId = null;
      break;
    }
  }
};

/** The stream could not be (re)opened, e.g. the answer was retried elsewhere. Reload to catch up. */
const onStreamError = async (chatId: string) => {
  streamErrors++;
  if (streamErrors > MAX_STREAM_ERRORS) {
    showSnackbar(t('chat.page.connectionLost'));
    return;
  }
  if (currentId === chatId) {
    await fetchChat(chatId, false);
  }
};

// --- loading ---

const fetchChat = async (id: string, initial: boolean) => {
  fetching.value = true;
  try {
    const data = await getChat(id);
    if (currentId !== id) {
      return;
    }
    stopStream();
    chat.value = data;
    const generating = data.messages.find(m => m.status === MessageStatus.GENERATING);
    if (generating) {
      startStream(id, generating.id);
    }
    if (initial) {
      await scrollToBottom(true);
    }
  } catch (e) {
    if (currentId !== id) {
      return;
    }
    if (e instanceof ApiError && e.status === 404) {
      showSnackbar(t('chat.page.notFound'));
      await navigateTo('/');
    } else {
      showSnackbar(t('chat.page.openFailed', {error: errorMessage(e)}));
    }
  } finally {
    fetching.value = false;
  }
};

const fetchRepositories = async () => {
  try {
    repositories.value = await getRepositories();
  } catch (e) {
    showSnackbar(t('repositories.listPage.loadFailed', {error: errorMessage(e)}));
  }
};

const fetchModels = async () => {
  try {
    models.value = await getModels();
    modelsLoaded.value = true;
  } catch (e) {
    showSnackbar(t('settings.preferences.page.modelsLoadFailed', {error: errorMessage(e)}));
  }
};

// The page is reused when navigating from one chat to another.
watch(() => route.params.id, async (id) => {
  if (typeof id !== 'string' || !id || id === currentId) {
    return;
  }
  stopStream();
  streamErrors = 0;
  currentId = id;
  chat.value = null;
  input.value = '';
  attachment.value = null;
  dialogRename.value = false;
  dialogDelete.value = false;
  dialogToolCall.value = false;
  presentedFile.value = null;
  dialogUsage.value = false;
  // `autofocus` covers the first chat; the page is reused for the next ones
  nextTick(() => messageInput.value?.focus());
  await fetchChat(id, true);
}, {immediate: true});

/** Escape closes the file, unless it is meant for a dialog or menu open above it. */
const onKeydown = (e: KeyboardEvent) => {
  if (e.key !== 'Escape' || !presentedFile.value || e.defaultPrevented) {
    return;
  }
  // still marked active while the overlay closes on this same key
  if (document.querySelector('.v-overlay--active:not(.v-tooltip)')) {
    return;
  }
  presentedFile.value = null;
};

onMounted(() => {
  window.addEventListener('scroll', onScroll, {passive: true});
  window.addEventListener('keydown', onKeydown);
  bodyObserver.observe(chatBody.value!);
  fetchRepositories();
  fetchModels();
});

onBeforeUnmount(() => {
  filePresented.value = false;
  window.removeEventListener('scroll', onScroll);
  window.removeEventListener('keydown', onKeydown);
  bodyObserver.disconnect();
  currentId = null;
  stopStream();
});

// --- composer ---

const doSend = async () => {
  if (!canSend.value) {
    return;
  }
  const chatId = chat.value!.id;
  sending.value = true;
  try {
    const [userMessage, assistantMessage] = await sendMessage(chatId, input.value,
        attachment.value?.uploaded?.id ?? null);
    if (chat.value?.id !== chatId) {
      return;
    }
    chat.value.messages.push(userMessage, assistantMessage);
    input.value = '';
    attachment.value = null;
    startStream(chatId, assistantMessage.id);
    await scrollToBottom(true);
    refreshChats().catch(() => {});
  } catch (e) {
    // the typed text stays in the composer
    if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_ATTACHMENT) {
      showSnackbar(t('chat.unknownAttachment'));
      attachment.value = null;
    } else if (e instanceof ApiError && e.code === ErrorCode.NO_MODEL_CONFIGURED) {
      showSnackbar(t('chat.noModelConfigured'));
    } else if (e instanceof ApiError && e.code === ErrorCode.RATE_LIMITED) {
      showSnackbar(t('chat.rateLimited'));
    } else {
      showSnackbar(t('chat.page.sendFailed', {error: errorMessage(e)}));
    }
  } finally {
    sending.value = false;
  }
};

const doStop = async () => {
  const message = generatingMessage.value;
  if (!chat.value || !message) {
    return;
  }
  stopping.value = true;
  try {
    // the stream then delivers `done` with status CANCELLED
    await cancelMessage(chat.value.id, message.id);
  } catch (e) {
    showSnackbar(t('chat.page.stopFailed', {error: errorMessage(e)}));
  } finally {
    stopping.value = false;
  }
};

const doRetry = async (message: MessageDto) => {
  if (!chat.value) {
    return;
  }
  const chatId = chat.value.id;
  retryingId.value = message.id;
  try {
    const next = await retryMessage(chatId, message.id);
    if (chat.value?.id !== chatId) {
      return;
    }
    const messages = chat.value.messages;
    const index = messages.findIndex(m => m.id === message.id);
    if (index >= 0) {
      messages[index] = next;
    } else {
      messages.push(next);
    }
    startStream(chatId, next.id);
    await scrollToBottom(false);
    refreshChats().catch(() => {});
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.NOT_RETRYABLE) {
      // someone else already retried or answered, show the current state
      showSnackbar(errorMessage(e));
      await fetchChat(chatId, false);
    } else if (e instanceof ApiError && e.code === ErrorCode.NO_MODEL_CONFIGURED) {
      showSnackbar(t('chat.noModelConfigured'));
    } else if (e instanceof ApiError && e.code === ErrorCode.RATE_LIMITED) {
      showSnackbar(t('chat.rateLimited'));
    } else {
      showSnackbar(t('chat.page.retryFailed', {error: errorMessage(e)}));
    }
  } finally {
    retryingId.value = null;
  }
};

// --- tool calls ---

const showToolCallDialog = (toolCall: ToolCallSummaryDto) => {
  toolCallDialog.value!.load(toolCall);
  dialogToolCall.value = true;
};

// --- usage ---

const showUsageDialog = (message: MessageDto) => {
  usageDialog.value!.load(message, modelNames.value.get(message.model_id ?? '') ?? null);
  dialogUsage.value = true;
};

// --- rename, model & delete ---

const showRenameDialog = () => {
  renameDialog.value!.load(chat.value!);
  dialogRename.value = true;
};

const doRename = async (title: string) => {
  if (await doUpdate(title, chat.value!.model_id, 'chat.page.renameFailed')) {
    dialogRename.value = false;
    showSnackbar(t('chat.page.renamed'));
  }
};

const doChangeModel = async (modelId: string | null) => {
  await doUpdate(chat.value!.title, modelId, 'chat.page.changeModelFailed');
};

/** Returns whether the update succeeded. `failedKey` is the text for errors, with the message as `error`. */
const doUpdate = async (title: string, modelId: string | null, failedKey: string): Promise<boolean> => {
  const chatId = chat.value!.id;
  loading.value = true;
  try {
    const updated = await updateChat(chatId, {title, model_id: modelId});
    if (chat.value?.id === chatId) {
      chat.value = {...chat.value, ...updated};
    }
    await refreshChats();
    return true;
  } catch (e) {
    if (e instanceof ApiError && e.code === ErrorCode.UNKNOWN_MODEL) {
      showSnackbar(t('chat.unknownModel'));
      await fetchModels();
    } else {
      showSnackbar(t(failedKey, {error: errorMessage(e)}));
    }
    return false;
  } finally {
    loading.value = false;
  }
};

const doDelete = async () => {
  const chatId = chat.value!.id;
  loading.value = true;
  try {
    await deleteChat(chatId);
    dialogDelete.value = false;
    stopStream();
    showSnackbar(t('chat.page.deleted'));
    await refreshChats();
    await navigateTo('/');
  } catch (e) {
    showSnackbar(t('chat.page.deleteFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
};
</script>

<style scoped>
.chat-layout {
  display: flex;
  align-items: flex-start;
}

.chat-page {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  min-height: calc(100dvh - var(--v-layout-top, 0px) - var(--v-layout-bottom, 0px));
}

.chat-column {
  width: 100%;
  max-width: 800px;
  margin: 0 auto;
  padding: 0 16px;
}

.chat-body {
  flex: 1;
  padding-top: 30px;
  padding-bottom: 24px;
}

.chat-title {
  overflow-wrap: anywhere;
}

.composer {
  position: sticky;
  bottom: 0;
  padding: 12px 0 24px;
  background: linear-gradient(to bottom, rgba(var(--v-theme-secondary), 0), rgb(var(--v-theme-secondary)) 24px);
}

/*
 * Stays in view while the chat scrolls with the window. It slides in by growing from the right, so
 * the chat narrows along with it; the content keeps its final width meanwhile (50cqw of the layout,
 * anchored to the right edge), so it does not reflow, and fades in once the panel is open.
 */
.file-panel {
  position: sticky;
  top: var(--v-layout-top, 0px);
  width: 50%;
  flex-shrink: 0;
  height: calc(100dvh - var(--v-layout-top, 0px) - var(--v-layout-bottom, 0px));
  display: flex;
  justify-content: flex-end;
  overflow: hidden;
}

.file-panel-content {
  width: 50cqw;
  height: 100%;
  flex-shrink: 0;
  /* none on the left, where the chat column has its padding */
  padding: 16px 16px 16px 0;
}

.file-panel-card {
  height: 100%;
  border-radius: 8px;
}

.file-panel-enter-active, .file-panel-leave-active {
  transition: width 250ms cubic-bezier(0.4, 0, 0.2, 1);
}

.file-panel-enter-from, .file-panel-leave-to {
  width: 0;
}

@keyframes file-panel-content-in {
  from {
    opacity: 0;
  }
}

@media screen and (min-width: 960px) {
  .chat-layout {
    /* for the width of the panel content; not below, where it would contain the fixed panel */
    container-type: inline-size;
  }

  /*
   * fades in once the panel has grown, so it runs on the content rather than on .file-panel-enter-active,
   * which goes at that point; not below, where the file slides in as a whole
   */
  .file-panel-content {
    animation: file-panel-content-in 200ms ease-out 400ms both;
  }

  /* on closing, the file goes at once and only its space shrinks while the chat recenters */
  .file-panel-leave-active .file-panel-content {
    visibility: hidden;
  }
}

/* too narrow for both, the file covers the chat until it is closed */
@media screen and (max-width: 959.98px) {
  .file-panel {
    position: fixed;
    top: var(--v-layout-top, 0px);
    left: 0;
    right: 0;
    bottom: 0;
    width: auto;
    height: auto;
    z-index: 1000;
  }

  .file-panel-content {
    width: 100%;
    padding: 0;
  }

  .file-panel-card {
    border-radius: 0;
  }

  .file-panel-enter-active, .file-panel-leave-active {
    transition: transform 250ms cubic-bezier(0.4, 0, 0.2, 1);
  }

  .file-panel-enter-from, .file-panel-leave-to {
    width: auto;
    transform: translateX(100%);
  }
}

@media (prefers-reduced-motion: reduce) {
  .file-panel-enter-active, .file-panel-leave-active {
    transition: none;
  }

  .file-panel-content {
    animation: none;
  }
}
</style>
