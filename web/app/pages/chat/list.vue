<template>
  <MainContainer :title="$t('chat.title')">
    <v-infinite-scroll side="end" @load="load">
      <v-list lines="two" bg-color="transparent">
        <v-list-item v-for="c in chats" :key="c.id" :to="'/chat/' + c.id" :title="c.title"
                     class="bg-surface mb-2" rounded>
          <template v-slot:subtitle>
            <span :title="formatDateTime(c.updated_at)">{{ formatRelative(c.updated_at) }}</span>
          </template>
        </v-list-item>
      </v-list>

      <template v-slot:empty>
        <p v-if="chats.length === 0" class="text-medium-emphasis">{{ $t('chat.noChats') }}</p>
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
import {errorMessage, getChats} from "~/utils/api";
import {formatDateTime, formatRelative, showSnackbar} from "~/utils/utils";
import MainContainer from "~/components/MainContainer.vue";
import {useI18n} from "#i18n";

const {t} = useI18n();

const PAGE_SIZE = 50;

type LoadStatus = 'ok' | 'empty' | 'error';

const chats = ref<ChatDto[]>([]);
let nextCursor: string | null = null;

/** Called by `v-infinite-scroll` on mount and whenever the end of the list comes into view. */
const load = async ({done}: { done: (status: LoadStatus) => void }) => {
  try {
    const page = await getChats(nextCursor, PAGE_SIZE);
    chats.value.push(...page.items);
    nextCursor = page.next_cursor;
    done(nextCursor === null ? 'empty' : 'ok');
  } catch (e) {
    showSnackbar(t('chat.loadFailed', {error: errorMessage(e)}));
    done('error');
  }
}
</script>
