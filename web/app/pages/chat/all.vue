<template>
  <MainContainer :title="$t('chat.allPage.title')">
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
          {{ search === null ? $t('chat.noChats') : $t('chat.allPage.noResults') }}
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
import MainContainer from "~/components/MainContainer.vue";
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

const submit = () => {
  search.value = input.value?.trim() || null;
  chats.value = [];
  nextCursor = null;
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
