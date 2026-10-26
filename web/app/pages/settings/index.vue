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
        <v-list-item v-for="p in pagesVisible" :key="p.route" :to="p.route" :title="p.label" :subtitle="p.description"
                     :prepend-icon="p.icon" append-icon="mdi-chevron-right"/>
      </v-list>
    </v-card>

    <template v-if="user?.role === UserRole.ADMIN">
      <div class="mt-12 mb-4 ml-4 ml-sm-0">{{ $t('settings.page.admin') }}</div>
      <v-card>
        <v-list lines="two">
          <v-list-item v-for="p in adminPages" :key="p.route" :to="p.route" :title="p.label" :subtitle="p.description"
                       :prepend-icon="p.icon" append-icon="mdi-chevron-right"/>
        </v-list>
      </v-card>
    </template>

    <v-btn @click="doLogout" class="mt-12" color="primary" prepend-icon="mdi-logout" :text="$t('settings.page.logout')"/>
  </MainContainer>
</template>

<script setup lang="ts">
import {computed} from "vue";
import {useTheme} from "vuetify";
import {useI18n} from "#i18n";
import {useUser} from "~/composables/states";
import {logout} from "~/utils/api";
import {UserRole} from "~/utils/model";
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

const pages = computed(() => [
  {
    route: '/settings/repositories',
    label: t('repositories.title'),
    description: t('settings.page.repositoriesSubtitle'),
    icon: 'mdi-source-repository',
    requiresRepositoryManagement: true,
  },
  {
    route: '/settings/account',
    label: t('settings.account.title'),
    description: t('settings.page.accountSubtitle'),
    icon: 'mdi-account-key',
  },
  {
    route: '/settings/profile',
    label: t('settings.profile.title'),
    description: t('settings.page.profileSubtitle'),
    icon: 'mdi-card-account-details',
  },
  {
    route: '/settings/preferences',
    label: t('settings.preferences.title'),
    description: t('settings.page.preferencesSubtitle'),
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
    description: t('settings.page.usersSubtitle'),
    icon: 'mdi-account-multiple',
  },
  {
    route: '/settings/admin/llm',
    label: t('admin.llm.title'),
    description: t('settings.page.llmSubtitle'),
    icon: 'mdi-robot',
  },
  {
    route: '/settings/admin/extraction',
    label: t('admin.extraction.title'),
    description: t('settings.page.extractionSubtitle'),
    icon: 'mdi-file-document-multiple',
  },
  {
    route: '/settings/admin/config',
    label: t('admin.config.title'),
    description: t('settings.page.configSubtitle'),
    icon: 'mdi-cog-transfer',
  },
]);

const doLogout = async () => {
  try {
    await logout();
  } finally {
    user.value = null;
  }
}
</script>
