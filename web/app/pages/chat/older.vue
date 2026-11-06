<template>
  <MainContainer :title="$t('chat.olderPage.title')">
    <!-- Enter submits the form, which has no submit button: the field prevents the default of clicks in it -->
    <form class="mb-6" @submit.prevent="submit">
      <v-text-field v-model="input" :placeholder="$t('common.search')" variant="solo" hide-details clearable
                    @click:clear="clear">
        <template v-slot:append-inner>
          <v-btn icon="mdi-magnify" variant="plain" density="comfortable"
                 :aria-label="$t('common.search')" :title="$t('common.search')" @click="submit"/>
        </template>
      </v-text-field>
    </form>

    <!-- remounted for every search, so it loads from the start -->
    <v-infinite-scroll :key="listKey" side="end" @load="load">
      <v-list lines="two" bg-color="transparent">
        <v-list-item v-for="c in chats" :key="c.id" :to="'/chat/' + c.id" :title="c.title"
                     class="bg-surface mb-2" rounded>
          <template v-slot:subtitle>
            <span :title="formatDateTime(c.updated_at)">{{ formatRelative(c.updated_at) }}</span>
          </template>
        </v-list-item>
      </v-list>

      <template v-slot:empty>
        <p v-if="chats.length === 0" class="text-medium-emphasis">
          {{ search === null ? $t('chat.noChats') : $t('chat.olderPage.noResults') }}
        </p>
      </template>

      <template v-slot:error="{ props }">
        <v-btn v-bind="props" variant="outlined" :text="$t('common.retry')"/>
      </template>
    </v-infinite-scroll>
  </MainContainer>
</template>

<script setup lang="ts">
import {ref} from "vue";
import type {ChatDto} from "~/utils/model";
import {errorMessage, getChats, searchChats} from "~/utils/api";
import {formatDateTime, formatRelative, showSnackbar} from "~/utils/utils";
import {refreshChats, useOlderChatsCursor} from "~/composables/states";
import MainContainer from "~/components/MainContainer.vue";
import {useI18n} from "#i18n";

const {t} = useI18n();

const PAGE_SIZE = 50;

type LoadStatus = 'ok' | 'empty' | 'error';

const olderChatsCursor = useOlderChatsCursor();

/** `null` once cleared. */
const input = ref<string | null>('');

/** The submitted search over all chats, `null` lists the older ones. */
const search = ref<string | null>(null);

/** Changed for every search, so the loads of the previous list are dropped. */
const listKey = ref(0);

/** The chats older than those in the navigation, so the list starts after its last one, or those found. */
const chats = ref<ChatDto[]>([]);

/** `undefined` before the first page, `null` once all are loaded. */
let nextCursor: string | null | undefined = undefined;

const submit = () => {
  search.value = input.value?.trim() || null;
  chats.value = [];
  nextCursor = undefined;
  listKey.value++;
}

const clear = () => {
  input.value = '';
  if (search.value !== null) {
    submit();
  }
}

/** Called by `v-infinite-scroll` on mount and whenever the end of the list comes into view. */
const load = async ({done}: { done: (status: LoadStatus) => void }) => {
  const key = listKey.value;
  const query = search.value;
  try {
    if (nextCursor === undefined && query === null) {
      // opened directly, before the navigation's chats were loaded
      if (olderChatsCursor.value === undefined) {
        await refreshChats();
      }
      if (key !== listKey.value) {
        return;
      }
      nextCursor = olderChatsCursor.value ?? null;
    }
    if (nextCursor === null) {
      done('empty');
      return;
    }
    // a search starts at the newest chat
    const page = query === null
        ? await getChats(nextCursor ?? null, PAGE_SIZE)
        : await searchChats(query, nextCursor ?? null, PAGE_SIZE);
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
