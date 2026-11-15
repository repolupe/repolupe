<template>
  <MainContainer :title="$t('chat.allPage.title')">
    <!-- Enter submits the form, which has no submit button: the field prevents the default of clicks in it -->
    <form class="mb-2" @submit.prevent="submit">
      <v-text-field v-model="input" :placeholder="$t('common.search')" variant="solo" hide-details clearable
                    @click:clear="clear">
        <template v-slot:append-inner>
          <v-btn icon="mdi-magnify" variant="plain" density="comfortable"
                 :aria-label="$t('common.search')" :title="$t('common.search')" @click="submit"/>
        </template>
      </v-text-field>
    </form>

    <!-- keeps its height while empty, so selecting the first chat doesn't move the list -->
    <div class="d-flex align-center flex-wrap mb-2" style="min-height: 44px; gap: 4px">
      <template v-if="selected.size > 0">
        <v-btn icon="mdi-close" variant="text" density="comfortable"
               :aria-label="$t('common.cancel')" :title="$t('common.cancel')" @click="clearSelection"/>
        <span class="ml-2">{{ $t('chat.allPage.selected', {count: selected.size}) }}</span>
        <v-spacer/>
        <v-btn v-if="allSelected" variant="text" prepend-icon="mdi-checkbox-blank-outline"
               :text="$t('chat.allPage.deselectAll')" @click="clearSelection"/>
        <v-btn v-else variant="text" prepend-icon="mdi-checkbox-multiple-marked-outline"
               :text="$t('chat.allPage.selectAll')" @click="selectAll"/>
        <v-btn variant="text" color="error" prepend-icon="mdi-delete"
               :text="$t('common.delete')" @click="dialogDelete = true"/>
      </template>
    </div>

    <!-- remounted for every search, so it loads from the start -->
    <v-infinite-scroll :key="listKey" side="end" @load="load">
      <v-list lines="two" bg-color="transparent">
        <v-list-item v-for="c in chats" :key="c.id" :to="'/chat/' + c.id" :title="c.title"
                     :active="selected.has(c.id)" color="primary" class="bg-surface mb-2" rounded>
          <template v-slot:prepend>
            <!-- a button, not a checkbox: preventing the click's default keeps the link from opening the chat -->
            <v-list-item-action start>
              <v-btn :icon="selected.has(c.id) ? 'mdi-checkbox-marked' : 'mdi-checkbox-blank-outline'"
                     :color="selected.has(c.id) ? 'primary' : undefined" variant="text" density="comfortable"
                     :aria-label="$t('chat.allPage.select')" :aria-pressed="selected.has(c.id)"
                     :title="$t('chat.allPage.select')" @click.stop.prevent="toggle(c.id)"/>
            </v-list-item-action>
          </template>
          <template v-slot:subtitle>
            <span :title="formatDateTime(c.updated_at)">{{ formatRelative(c.updated_at) }}</span>
          </template>
        </v-list-item>
      </v-list>

      <template v-slot:empty>
        <p v-if="chats.length === 0" class="text-medium-emphasis">
          {{ search === null ? $t('chat.noChats') : $t('chat.allPage.noResults') }}
        </p>
      </template>

      <template v-slot:error="{ props }">
        <v-btn v-bind="props" variant="outlined" :text="$t('common.retry')"/>
      </template>
    </v-infinite-scroll>

    <GenericDeleteDialog v-model="dialogDelete" :loading="deleting" :title="$t('chat.allPage.deleteTitle')"
                         @delete="doDelete">
      {{ $t('chat.allPage.deleteConfirm', selected.size) }}
    </GenericDeleteDialog>
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import type {ChatDto} from "~/utils/model";
import {deleteChats, errorMessage, getChats, searchChats} from "~/utils/api";
import {formatDateTime, formatRelative, showSnackbar} from "~/utils/utils";
import {refreshChats} from "~/composables/states";
import MainContainer from "~/components/MainContainer.vue";
import GenericDeleteDialog from "~/components/dialogs/GenericDeleteDialog.vue";
import {useI18n} from "#i18n";

const {t} = useI18n();

const PAGE_SIZE = 50;

type LoadStatus = 'ok' | 'empty' | 'error';

/** `null` once cleared. */
const input = ref<string | null>('');

/** The submitted search, `null` lists all chats. */
const search = ref<string | null>(null);

/** Changed for every search, so the loads of the previous list are dropped. */
const listKey = ref(0);

/** All chats, newest first, or those found. */
const chats = ref<ChatDto[]>([]);

/** `null` for the first page, then where the next one starts. */
let nextCursor: string | null = null;

/** The ids of the selected chats, all of them listed. */
const selected = ref(new Set<string>());

const allSelected = computed(() => chats.value.length > 0 && selected.value.size === chats.value.length);

const dialogDelete = ref(false);
const deleting = ref(false);

const submit = () => {
  search.value = input.value?.trim() || null;
  chats.value = [];
  nextCursor = null;
  selected.value = new Set();
  listKey.value++;
}

const clear = () => {
  input.value = '';
  if (search.value !== null) {
    submit();
  }
}

const clearSelection = () => {
  selected.value = new Set();
}

const toggle = (id: string) => {
  const next = new Set(selected.value);
  if (!next.delete(id)) {
    next.add(id);
  }
  selected.value = next;
}

/** Selects the chats loaded so far. */
const selectAll = () => {
  selected.value = new Set(chats.value.map(c => c.id));
}

const doDelete = async () => {
  const ids = [...selected.value];
  deleting.value = true;
  try {
    await deleteChats(ids);
    const deleted = new Set(ids);
    chats.value = chats.value.filter(c => !deleted.has(c.id));
    dialogDelete.value = false;
    clearSelection();
    showSnackbar(t('chat.allPage.deleted', ids.length));
    refreshChats().catch(() => {});
  } catch (e) {
    showSnackbar(t('chat.allPage.deleteFailed', {error: errorMessage(e)}));
  } finally {
    deleting.value = false;
  }
}

/** Called by `v-infinite-scroll` on mount and whenever the end of the list comes into view. */
const load = async ({done}: { done: (status: LoadStatus) => void }) => {
  const key = listKey.value;
  const query = search.value;
  try {
    const page = query === null
        ? await getChats(nextCursor, PAGE_SIZE)
        : await searchChats(query, nextCursor, PAGE_SIZE);
    if (key !== listKey.value) {
      return;
    }
    chats.value.push(...page.items);
    nextCursor = page.next_cursor;
    done(nextCursor === null ? 'empty' : 'ok');
  } catch (e) {
    if (key !== listKey.value) {
      return;
    }
    showSnackbar(t('chat.loadFailed', {error: errorMessage(e)}));
    done('error');
  }
}
</script>
