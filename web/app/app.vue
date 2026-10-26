<template>
  <v-app>
    <Navigation />
    <v-main class="bg-secondary">
      <NuxtPage />
    </v-main>
  </v-app>

  <v-snackbar v-model="snackbar" location="bottom right">
    {{ snackbarText }}

    <template v-slot:actions>
      <v-btn
          variant="text"
          @click="snackbar = false"
          icon="mdi-close"
      />
    </template>
  </v-snackbar>
</template>

<script lang="ts" setup>
import {onMounted, onUnmounted, ref, watch} from "vue";
import {navigateTo, useHead} from "#app";
import {initSnackbar, showSnackbar} from "~/utils/utils";
import {errorMessage, initAPI, logout} from "~/utils/api";
import {
    PRODUCT_NAME,
    refreshChats,
    refreshInstanceName,
    useChats,
    useInstanceName,
    useInstanceTitle,
    useOlderChatsCursor,
    useUser,
} from "~/composables/states";
import {useI18n} from "#i18n";

const {t} = useI18n();

const user = useUser();
const chats = useChats();
const olderChatsCursor = useOlderChatsCursor();
const instanceName = useInstanceName();
const instanceTitle = useInstanceTitle();

const snackbar = ref(false);
const snackbarText = ref<string | null>(null);

// The favicon follows the OS theme (not the app theme) because it is shown in the browser UI.
// Bound reactively since browsers only evaluate <link media> once at page load.
const darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
const prefersDark = ref(darkQuery.matches);
const onDarkChange = (e: MediaQueryListEvent) => {
  prefersDark.value = e.matches;
};
darkQuery.addEventListener('change', onDarkChange);
onUnmounted(() => darkQuery.removeEventListener('change', onDarkChange));

useHead({
  // pages with a title of their own override it
  title: instanceTitle,
  link: [
    {
      key: 'favicon',
      rel: 'icon',
      type: 'image/png',
      href: () => prefersDark.value ? '/favicon-white.png' : '/favicon.png',
    },
  ],
});

watch(user, async (next, prev) => {
  if (next && !next.must_change_password && (!prev || prev.must_change_password)) {
    // login, the session was restored from the cookie, or a required password change is done
    try {
      await refreshChats();
    } catch (e) {
      showSnackbar(t('chat.loadFailed', {error: errorMessage(e)}));
    }
  } else if (next?.must_change_password && prev && !prev.must_change_password) {
    // required while logged in
    try {
      await logout();
    } finally {
      user.value = null;
    }
  } else if (prev && !next) {
    // logout, or the session expired
    chats.value = [];
    olderChatsCursor.value = undefined;
    navigateTo('/login');
  }
}, {immediate: true});

onMounted(() => {
  initSnackbar((text: string) => {
    snackbarText.value = text;
    snackbar.value = true;
  });
  initAPI(() => {
    user.value = null;
  }, () => {
    // an admin required it while the user was logged in
    if (user.value && !user.value.must_change_password) {
      // the watch on the user logs them out
      user.value = {...user.value, must_change_password: true};
    }
  });
  refreshInstanceName().catch(() => {
    // shown instead, e.g. by the navigation, which waits for the name
    instanceName.value = PRODUCT_NAME;
  });
});
</script>
