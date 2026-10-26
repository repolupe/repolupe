<template>
  <MainContainer :title="$t('settings.title')">
    <div class="mb-4 ml-4 ml-sm-0">{{ $t('settings.page.app') }}</div>
    <v-card>
      <v-list lines="two">
        <!-- stored in the browser, so it applies right away -->
        <v-list-item :title="$t('settings.themeMode.title')" :subtitle="themeModeLabel(themeMode)"
                     :prepend-icon="THEME_MODE_ICONS[themeMode]" append-icon="mdi-menu-down">
          <v-menu activator="parent">
            <v-list :selected="[themeMode]" color="primary" mandatory>
              <v-list-item v-for="mode in Object.values(ThemeMode)" :key="mode" :value="mode"
                           :title="themeModeLabel(mode)" :prepend-icon="THEME_MODE_ICONS[mode]"
                           @click="setThemeMode(mode)"/>
            </v-list>
          </v-menu>
        </v-list-item>
      </v-list>
    </v-card>

    <div class="mt-12 mb-4 ml-4 ml-sm-0">{{ $t('settings.page.user') }}</div>
    <v-card>
      <v-list lines="two">
        <v-list-item v-for="p in pagesVisible" :key="p.route" :to="p.route" :title="p.label" :subtitle="p.state"
                     :prepend-icon="p.icon" append-icon="mdi-chevron-right"/>
      </v-list>
    </v-card>

    <template v-if="user?.role === UserRole.ADMIN">
      <div class="mt-12 mb-4 ml-4 ml-sm-0">{{ $t('settings.page.admin') }}</div>
      <v-card>
        <v-list>
          <v-list-item v-for="p in adminPages" :key="p.route" :to="p.route" :title="p.label"
                       :prepend-icon="p.icon" append-icon="mdi-chevron-right"/>
        </v-list>
      </v-card>
    </template>

    <v-btn @click="doLogout" class="mt-12" color="primary" prepend-icon="mdi-logout" :text="$t('settings.page.logout')"/>
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, onMounted, ref} from "vue";
import {useTheme} from "vuetify";
import {useI18n} from "#i18n";
import {useUser} from "~/composables/states";
import {getModels, getRepositories, logout} from "~/utils/api";
import {type ModelDto, UserRole} from "~/utils/model";
import {THEME_MODE_ICONS, ThemeMode, writeThemeMode} from "~/utils/theme";
import MainContainer from "~/components/MainContainer.vue";

const {t} = useI18n();
const user = useUser();
const theme = useTheme();

const themeMode = computed(() => theme.isSystem.value ? ThemeMode.SYSTEM : theme.name.value as ThemeMode);

const themeModeLabel = (mode: ThemeMode) => ({
  [ThemeMode.SYSTEM]: t('settings.themeMode.system'),
  [ThemeMode.LIGHT]: t('settings.themeMode.light'),
  [ThemeMode.DARK]: t('settings.themeMode.dark'),
})[mode];

const setThemeMode = (mode: ThemeMode) => {
  theme.change(mode);
  writeThemeMode(mode);
}

// For the states of the pages, `null` until loaded (or if loading failed, then the state is left out).
const repositoryCount = ref<number | null>(null);
const models = ref<ModelDto[] | null>(null);

// The model the user's chats use: their own, else the default one. `undefined` if there is none.
const modelName = computed(() => {
  const chosen = models.value?.find(m => m.id === user.value?.default_model_id)
    ?? models.value?.find(m => m.is_default);
  return chosen?.display_name;
});

const pages = computed(() => [
  {
    route: '/settings/repositories',
    label: t('repositories.title'),
    state: repositoryCount.value !== null ? t('settings.page.repositoryCount', repositoryCount.value) : undefined,
    icon: 'mdi-source-repository',
    requiresRepositoryManagement: true,
  },
  {
    route: '/settings/account',
    label: t('settings.account.title'),
    state: [user.value?.user_name, user.value?.email].filter(Boolean).join(' · '),
    icon: 'mdi-account-key',
  },
  {
    route: '/settings/profile',
    label: t('settings.profile.title'),
    state: user.value?.full_name ?? user.value?.first_name ?? user.value?.about ?? t('settings.page.profileEmpty'),
    icon: 'mdi-card-account-details',
  },
  {
    route: '/settings/preferences',
    label: t('settings.preferences.title'),
    // the server uses the browser's language for users without one
    state: [modelName.value, user.value?.locale ?? navigator.language].filter(Boolean).join(' · '),
    icon: 'mdi-tune',
  },
]);

// Users who cannot manage repositories only use the ones shared with them in chats.
const pagesVisible = computed(() =>
    pages.value.filter(p => !p.requiresRepositoryManagement || user.value?.can_manage_repositories));

const adminPages = computed(() => [
  {
    route: '/settings/admin/users',
    label: t('admin.users.title'),
    icon: 'mdi-account-multiple',
  },
  {
    route: '/settings/admin/llm',
    label: t('admin.llm.title'),
    icon: 'mdi-robot',
  },
  {
    route: '/settings/admin/extraction',
    label: t('admin.extraction.title'),
    icon: 'mdi-file-document-multiple',
  },
  {
    route: '/settings/admin/config',
    label: t('admin.config.title'),
    icon: 'mdi-cog-transfer',
  },
  {
    route: '/settings/admin/server',
    label: t('admin.server.title'),
    icon: 'mdi-server',
  },
]);

// The states are only a summary, a failed request leaves them out instead of showing an error.
onMounted(() => {
  if (user.value?.can_manage_repositories) {
    getRepositories().then(r => repositoryCount.value = r.length).catch(() => {});
  }
  getModels().then(m => models.value = m).catch(() => {});
});

const doLogout = async () => {
  try {
    await logout();
  } finally {
    user.value = null;
  }
}
</script>
