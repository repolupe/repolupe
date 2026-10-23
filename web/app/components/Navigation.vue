<template>
  <div>
    <v-app-bar color="primary" v-if="user && !user.must_change_password && $vuetify.display.mdAndDown">
      <v-app-bar-nav-icon variant="text" @click.stop="drawerVisible = !drawerVisible"></v-app-bar-nav-icon>

      <v-toolbar-title><InstanceTitle/></v-toolbar-title>
    </v-app-bar>

    <v-navigation-drawer v-if="user && !user.must_change_password" class="bg-primary" v-model="drawerVisible" :rail="railActive">
      <div class="pt-6 pb-4 px-4" :class="{'header-rail': railActive}" style="display: flex; align-items: center;">
        <div class="logo">
          <!-- smaller when collapsed, so it lines up with the icons below instead of filling the width -->
          <v-img src="/logo-512-white.webp" :alt="$t('app.logoAlt')" :width="logoSize" :height="logoSize"/>
          <!-- collapsed, the logo turns into the expand button on hover -->
          <v-btn v-if="railActive" class="expand-btn" icon variant="text" :size="logoSize"
                 :aria-label="$t('app.navigation.expandNavigation')" @click="toggleRail">
            <v-icon icon="mdi-dock-left"/>
            <v-tooltip activator="parent" location="end" :text="$t('app.navigation.expand')"/>
          </v-btn>
        </div>
        <template v-if="!railActive">
          <div class="pl-4" style="display: flex; flex-direction: column; justify-content: center; flex: 1; min-width: 0;">
            <p class="text-body-1 font-weight-bold mb-0 fade-overflow"><InstanceTitle/></p>
            <p class="mb-0 fade-overflow">{{ user.first_name || user.full_name || user.user_name }}</p>
          </div>
          <!-- on mobile, the drawer is an overlay that is closed instead -->
          <v-btn v-if="!display.mobile.value" class="collapse-btn ml-1 mr-n2" icon variant="text"
                 size="small" :aria-label="$t('app.navigation.collapseNavigation')" @click="toggleRail">
            <v-icon icon="mdi-dock-left"/>
            <v-tooltip activator="parent" location="bottom" :text="$t('app.navigation.collapse')"/>
          </v-btn>
        </template>
      </div>

      <v-list density="compact" nav>
        <v-list-item prepend-icon="mdi-plus" :title="$t('app.navigation.newChat')" to="/" exact>
          <v-tooltip activator="parent" location="end" :text="$t('app.navigation.newChat')" :disabled="!railActive"/>
        </v-list-item>

        <v-list-subheader v-if="!railActive" class="mt-2 text-grey-lighten-2">{{ $t('chat.title') }}</v-list-subheader>
        <v-divider v-else class="my-2"/>

        <v-list-item v-for="c in chats" :key="c.id" :to="'/chat/' + c.id" :title="c.title"
                     prepend-icon="mdi-message-text-outline">
          <v-tooltip activator="parent" location="end" :text="c.title" :disabled="!railActive"/>
        </v-list-item>

        <template v-if="chats.length === 0">
          <v-list-item v-if="!railActive" class="text-grey-lighten-1" :title="$t('chat.noChats')"/>
        </template>
        <v-list-item v-else prepend-icon="mdi-dots-horizontal" :title="$t('app.navigation.allChats')" to="/chat/list">
          <v-tooltip activator="parent" location="end" :text="$t('app.navigation.allChats')" :disabled="!railActive"/>
        </v-list-item>
      </v-list>

      <!-- the demo has no settings -->
      <template v-if="!DEMO" v-slot:append>
        <v-list density="compact" nav>
          <!-- also highlighted on the subpages, which are not nested routes of the page -->
          <v-list-item to="/settings" :title="$t('settings.title')" prepend-icon="mdi-cog"
                       :active="route.path.startsWith('/settings')">
            <v-tooltip activator="parent" location="end" :text="$t('settings.title')" :disabled="!railActive"/>
          </v-list-item>
        </v-list>
      </template>
    </v-navigation-drawer>
  </div>
</template>

<script lang="ts" setup>
import {computed, ref, watch} from "vue";
import {useDisplay} from "vuetify";
import {useRoute} from "#app";
import {useChats, useFilePresented, useUser} from "~/composables/states";
import InstanceTitle from "~/components/InstanceTitle.vue";
import {DEMO} from "~/utils/demo";

const user = useUser();
const chats = useChats();
const filePresented = useFilePresented();
const route = useRoute();

const drawerVisible = ref(false);

const display = useDisplay();

const RAIL_KEY = 'navigationRail';

/** Whether the user collapsed the drawer to icons, remembered per browser. */
const rail = ref(readRail());

/**
 * Collapsed while a file is shown next to the chat on smaller desktops, where the drawer would
 * narrow both. Wider screens have room for all three, and below desktop the drawer is an overlay.
 */
const autoRail = computed(() => filePresented.value && display.lg.value);

/** Whether the user expanded the drawer while {@link autoRail} applies, until it no longer does. */
const autoRailDismissed = ref(false);

watch(autoRail, (next) => {
  if (!next) {
    autoRailDismissed.value = false;
  }
});

/** Not on mobile, where the drawer is a full-width overlay. */
const railActive = computed(() =>
    !display.mobile.value && (rail.value || (autoRail.value && !autoRailDismissed.value)));

const logoSize = computed(() => railActive.value ? 24 : 40);

function readRail(): boolean {
  try {
    return localStorage.getItem(RAIL_KEY) === 'true';
  } catch {
    return false;
  }
}

function toggleRail() {
  if (autoRail.value && !rail.value) {
    // only for this file, the preference stays
    autoRailDismissed.value = !autoRailDismissed.value;
    return;
  }
  rail.value = !rail.value;
  try {
    localStorage.setItem(RAIL_KEY, String(rail.value));
  } catch {
    // only a convenience
  }
}

watch(user, (next, prev) => {
  if (!prev && next && display.lgAndUp.value) {
    drawerVisible.value = true;
  }
}, {immediate: true});
</script>

<style scoped>
.logo {
  position: relative;
  flex-shrink: 0;
}

.logo > .v-img {
  transition: opacity 150ms, width 200ms, height 200ms;
}

.expand-btn {
  position: absolute;
  inset: 0;
  opacity: 0;
  transition: opacity 150ms;
}

.header-rail:hover .expand-btn, .expand-btn:focus-visible {
  opacity: 1;
}

.header-rail:hover .logo > .v-img, .header-rail:has(.expand-btn:focus-visible) .logo > .v-img {
  opacity: 0;
}

/* there, but not competing with the navigation */
.collapse-btn {
  opacity: 0.6;
  transition: opacity 150ms;
}

.collapse-btn:hover, .collapse-btn:focus-visible {
  opacity: 1;
}

/* Long names are cut off with a fade instead of wrapping. */
.fade-overflow {
  white-space: nowrap;
  overflow: hidden;
  mask-image: linear-gradient(to right, black calc(100% - 24px), transparent);
}
</style>
