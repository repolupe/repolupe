<template>
  <ToolCallPanel :icon="CHANGE_ICONS[props.toolCall.name] ?? 'mdi-pencil-outline'" :tool-call="props.toolCall"
                 :repositories="props.repositories" :fetching="fetching" :error="error" :fill="!!pdfUrl"
                 :title="subject" @close="emit('close')">
    <template v-slot:title-append>
      <v-chip v-if="change && applied" color="success" size="small" variant="tonal"
              prepend-icon="mdi-check" :text="$t('chat.proposedCommitPanel.applied')" class="flex-shrink-0 ml-2"
              :title="$t('chat.proposedCommitPanel.appliedAt',
                  {relative: formatRelative(change.committed_at), dateTime: formatDateTime(change.committed_at)})"/>
    </template>
    <template v-slot:actions>
      <v-menu v-if="diff" location="bottom end">
        <template v-slot:activator="{ props: menuProps }">
          <v-btn v-bind="menuProps" icon="mdi-dots-vertical" variant="text" size="small"
                 :title="$t('chat.proposedCommitPanel.more')" :aria-label="$t('chat.proposedCommitPanel.more')"/>
        </template>
        <v-list density="compact">
          <v-list-item prepend-icon="mdi-download" :title="$t('chat.proposedCommitPanel.downloadPatch')" @click="download"/>
        </v-list>
      </v-menu>
    </template>

    <div v-if="diff" class="d-flex flex-column ga-4 pa-4" :class="{'pdf-layout': pdfUrl}">
      <p v-if="body" class="text-body-2 text-medium-emphasis commit-body">{{ body }}</p>

      <v-alert v-if="change?.error" :type="change.status === ProposedCommitStatus.CONFLICT ? 'warning' : 'error'"
               variant="tonal" density="compact" :text="change.error"/>

      <div v-if="diff.moves" class="moves">
        <div v-for="(move, i) in diff.moves" :key="i" class="move"
             :aria-label="$t('chat.proposedCommitPanel.movedTo', {from: move.from, to: move.to})">
          <span class="move-path">{{ move.from }}</span>
          <v-icon icon="mdi-arrow-right" size="16" class="text-medium-emphasis" aria-hidden="true"/>
          <span class="move-path">{{ move.to }}</span>
          <span v-if="move.folder_files !== null" class="text-caption text-medium-emphasis">
            {{ $t('chat.proposedCommitPanel.folderFiles', move.folder_files) }}
          </span>
        </div>
      </div>

      <v-alert v-else-if="!applied && diff.kind === DiffFileKind.DELETED" type="warning" variant="tonal" density="compact"
               icon="mdi-delete-outline" :text="$t('chat.proposedCommitPanel.willDelete')"/>
      <v-alert v-else-if="!applied && diff.kind === DiffFileKind.ADDED" type="info" variant="tonal" density="compact"
               icon="mdi-file-plus-outline" :text="$t('chat.proposedCommitPanel.willCreate')"/>

      <div v-if="diff.hunks.length > 0">
        <div class="d-flex align-center ga-4 text-caption text-medium-emphasis mb-2">
          <span class="d-flex align-center ga-1">
            <span class="legend legend-removed"/>{{ $t('chat.proposedCommitPanel.removed') }}
          </span>
          <span class="d-flex align-center ga-1">
            <span class="legend legend-added"/>{{ $t('common.added') }}
          </span>
        </div>
        <div class="diff">
          <template v-for="(hunk, h) in diff.hunks" :key="h">
            <div v-if="hunk.skipped" class="diff-gap" :title="$t('chat.proposedCommitPanel.unchangedLines')">⋯</div>
            <div v-for="(line, i) in hunk.lines" :key="i" class="diff-line"
                 :class="[`diff-${line.kind.toLowerCase()}`, {'diff-table': lineText(line).trimStart().startsWith('|')}]"
                 :aria-label="line.kind === DiffLineKind.REMOVED
                     ? $t('chat.proposedCommitPanel.removedLine', {text: lineText(line)})
                     : line.kind === DiffLineKind.ADDED ? $t('chat.proposedCommitPanel.addedLine', {text: lineText(line)})
                     : undefined">
              <span class="diff-sign" aria-hidden="true">{{ SIGNS[line.kind] }}</span>
              <span class="diff-text"><template v-for="(part, p) in line.parts" :key="p"><mark
                  v-if="part.changed">{{ part.text }}</mark><template v-else>{{ part.text }}</template></template></span>
            </div>
          </template>
        </div>
      </div>
      <iframe v-else-if="pdfUrl" :src="pdfUrl" :title="path" class="file-pdf"/>
      <p v-else-if="diff.kind !== DiffFileKind.DELETED && !diff.moves" class="text-body-2 text-medium-emphasis">
        {{ previewError ?? $t('chat.proposedCommitPanel.noPreview') }}
      </p>
    </div>

    <template v-if="diff && change && !applied" v-slot:footer>
      <v-divider/>
      <div class="d-flex flex-wrap align-center justify-end ga-3 pa-3 pl-4">
        <span class="text-caption text-medium-emphasis flex-grow-1">
          <template v-if="!change.can_commit">{{ $t('chat.proposedCommitPanel.cannotCommit') }}</template>
        </span>
        <v-btn v-if="change.can_commit && change.status === ProposedCommitStatus.PROPOSED && user && !user.auto_commit"
               variant="text" class="text-none"
               :text="$t('chat.proposedCommitPanel.enableAutoCommit')" @click="dialogAutoCommit = true"/>
        <v-btn v-if="change.can_commit" color="primary" variant="elevated" prepend-icon="mdi-check" class="text-none"
               :loading="committing" :text="applyLabel" @click="commit"/>
      </div>
      <GenericConfirmDialog v-model="dialogAutoCommit" :loading="enablingAutoCommit"
                            :title="$t('chat.proposedCommitPanel.autoCommitTitle')"
                            :confirm-text="$t('chat.proposedCommitPanel.autoCommitConfirm')" confirm-icon="mdi-check-circle"
                            @confirm="enableAutoCommit">
        {{ $t('chat.proposedCommitPanel.autoCommitText') }}
      </GenericConfirmDialog>
    </template>
  </ToolCallPanel>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, ref, watch} from "vue";
import {useI18n} from "#i18n";
import {
  DiffFileKind,
  DiffLineKind,
  ProposedCommitStatus,
  type DiffLineDto,
  type ProposedCommitDto,
  type FileDiffDto,
  type RepositoryDto,
  type ToolCallSummaryDto,
} from "~/utils/model";
import {
  commitProposedCommit,
  errorMessage,
  getProposedCommit,
  getProposedCommitDiff,
  getProposedCommitFile,
  getProposedCommitPatch,
  setMyAutoCommit,
} from "~/utils/api";
import {refreshUser, useUser} from "~/composables/states";
import {CHANGE_ICONS, fileName, formatDateTime, formatRelative, showSnackbar, toolCallPath} from "~/utils/utils";
import ToolCallPanel from "~/components/chat/panel/ToolCallPanel.vue";
import GenericConfirmDialog from "~/components/dialogs/GenericConfirmDialog.vue";

const {t} = useI18n();
const user = useUser();

const props = defineProps<{
  chatId: string,
  /** The `change_file`, `move_files` or `save_attachment` call that proposed the change. */
  toolCall: ToolCallSummaryDto,
  repositories: RepositoryDto[],
}>();

const emit = defineEmits<{
  (e: 'close'): void,
}>();

const SIGNS: Record<DiffLineKind, string> = {
  [DiffLineKind.CONTEXT]: '',
  [DiffLineKind.REMOVED]: '−',
  [DiffLineKind.ADDED]: '+',
};

const lineText = (line: DiffLineDto) => line.parts.map(part => part.text).join('');

const diff = ref<FileDiffDto | null>(null);
/** Whether it was committed. */
const change = ref<ProposedCommitDto | null>(null);
/** An object URL of the proposed file if it is a PDF, which the patch has no diff of. */
const pdfUrl = ref<string | null>(null);
/** Why the PDF can't be shown. */
const previewError = ref<string | null>(null);
const error = ref<string | null>(null);
const fetching = ref(false);
const committing = ref(false);
const dialogAutoCommit = ref(false);
const enablingAutoCommit = ref(false);

const path = computed(() => toolCallPath(props.toolCall) ?? '');

const applied = computed(() => change.value?.status === ProposedCommitStatus.COMMITTED);

const applyLabel = computed(() => change.value?.status === ProposedCommitStatus.PROPOSED
    ? t('chat.proposedCommitPanel.apply') : t('chat.proposedCommitPanel.tryAgain'));

const message = computed(() => {
  const value = props.toolCall.input?.message;
  return typeof value === 'string' ? value.trim() : '';
});

const subject = computed(() => message.value.split('\n')[0] ?? '');
const body = computed(() => message.value.split('\n').slice(1).join('\n').trim());

const setPdfUrl = (url: string | null) => {
  if (pdfUrl.value) {
    URL.revokeObjectURL(pdfUrl.value);
  }
  pdfUrl.value = url;
};

/** The proposed PDF as an object URL, or why it can't be shown. */
const fetchPdf = async (id: string): Promise<{ url: string | null, error: string | null }> => {
  try {
    const {blob} = await getProposedCommitFile(props.chatId, id);
    return {url: URL.createObjectURL(blob), error: null};
  } catch (e) {
    return {url: null, error: errorMessage(e)};
  }
};

const fetchDiff = async () => {
  const id = props.toolCall.id;
  diff.value = null;
  change.value = null;
  setPdfUrl(null);
  previewError.value = null;
  error.value = null;
  fetching.value = true;
  try {
    const [loadedDiff, loadedChange] = await Promise.all([
      getProposedCommitDiff(props.chatId, id),
      getProposedCommit(props.chatId, id),
    ]);
    const pdf = loadedDiff.hunks.length === 0 && loadedDiff.kind !== DiffFileKind.DELETED
    && !!loadedChange.path?.toLowerCase().endsWith('.pdf')
        ? await fetchPdf(id)
        : null;
    if (props.toolCall.id === id) {
      diff.value = loadedDiff;
      change.value = loadedChange;
      setPdfUrl(pdf?.url ?? null);
      previewError.value = pdf?.error ?? null;
    } else if (pdf?.url) {
      URL.revokeObjectURL(pdf.url);
    }
  } catch (e) {
    if (props.toolCall.id === id) {
      error.value = errorMessage(e);
    }
  } finally {
    if (props.toolCall.id === id) {
      fetching.value = false;
    }
  }
};

const commit = async () => {
  const id = props.toolCall.id;
  committing.value = true;
  try {
    const committed = await commitProposedCommit(props.chatId, id);
    if (props.toolCall.id === id) {
      change.value = committed;
    }
    if (committed.status === ProposedCommitStatus.COMMITTED) {
      showSnackbar(committed.path ? t('chat.proposedCommitPanel.appliedTo', {name: fileName(committed.path)})
          : t('chat.proposedCommitPanel.appliedMoves'));
      // unless the user opened another file meanwhile
      if (props.toolCall.id === id) {
        emit('close');
      }
    }
  } catch (e) {
    showSnackbar(t('chat.proposedCommitPanel.applyFailed', {error: errorMessage(e)}));
  } finally {
    if (props.toolCall.id === id) {
      committing.value = false;
    }
  }
};

/** Turns on the user's `auto_commit`, which applies the changes of later answers, and commits this one. */
const enableAutoCommit = async () => {
  enablingAutoCommit.value = true;
  try {
    await setMyAutoCommit(true);
    await refreshUser();
  } catch (e) {
    showSnackbar(t('settings.preferences.page.autoCommitSaveFailed', {error: errorMessage(e)}));
    return;
  } finally {
    enablingAutoCommit.value = false;
  }
  dialogAutoCommit.value = false;
  await commit();
};

const download = async () => {
  let patch: string;
  try {
    patch = await getProposedCommitPatch(props.chatId, props.toolCall.id);
  } catch (e) {
    showSnackbar(t('chat.proposedCommitPanel.downloadFailed', {error: errorMessage(e)}));
    return;
  }
  const url = URL.createObjectURL(new Blob([patch], {type: 'text/x-patch'}));
  const link = document.createElement('a');
  link.href = url;
  link.download = `${fileName(path.value) || 'moves'}.patch`;
  link.click();
  URL.revokeObjectURL(url);
};

watch(() => props.toolCall.id, fetchDiff, {immediate: true});

// PDFs can be large
onBeforeUnmount(() => setPdfUrl(null));
</script>

<style scoped>
.commit-body {
  white-space: pre-wrap;
}

.legend {
  display: inline-block;
  width: 12px;
  height: 12px;
  border-radius: 3px;
}

.legend-removed {
  background: rgba(var(--v-theme-error), 0.3);
}

.legend-added {
  background: rgba(var(--v-theme-success), 0.3);
}

.diff {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.85rem;
  line-height: 1.6;
  border: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
  border-radius: 8px;
  padding: 6px 0;
  overflow-x: auto;
}

.diff-line {
  display: flex;
  min-height: 1.6em;
}

.diff-sign {
  flex: 0 0 24px;
  text-align: center;
  user-select: none;
  font-weight: 600;
}

.diff-text {
  flex: 1;
  min-width: 0;
  padding-right: 12px;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

/* Wrapping a table row would break its columns, so tables scroll sideways instead. */
.diff-table {
  min-width: max-content;
}

.diff-table .diff-text {
  white-space: pre;
}

.diff-context {
  opacity: 0.7;
}

.diff-removed {
  background: rgba(var(--v-theme-error), 0.1);
}

.diff-removed .diff-sign {
  color: rgb(var(--v-theme-error));
}

.diff-added {
  background: rgba(var(--v-theme-success), 0.1);
}

.diff-added .diff-sign {
  color: rgb(var(--v-theme-success));
}

.diff mark {
  color: inherit;
  border-radius: 3px;
}

.diff-removed mark {
  background: rgba(var(--v-theme-error), 0.3);
  text-decoration: line-through;
}

.diff-added mark {
  background: rgba(var(--v-theme-success), 0.3);
}

/* The PDF viewer takes the height the commit message and the alerts leave. */
.pdf-layout {
  height: 100%;
}

/* Alerts grow in a flex container */
.pdf-layout > :not(.file-pdf) {
  flex: none;
}

.file-pdf {
  display: block;
  flex: 1;
  width: 100%;
  min-height: 0;
  border: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
  border-radius: 8px;
}

.moves {
  display: flex;
  flex-direction: column;
  gap: 8px;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.85rem;
}

.move {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 8px;
}

.move-path {
  overflow-wrap: anywhere;
}

.diff-gap {
  padding: 0 12px;
  text-align: center;
  opacity: 0.5;
  user-select: none;
}
</style>
