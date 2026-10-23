<template>
  <MainContainer :title="$t('settings.title')">
    <v-card>
      <v-list lines="two">
        <v-list-item v-for="p in pagesVisible" :key="p.route" :to="p.route" :title="p.label" :subtitle="p.description"
                     :prepend-icon="p.icon" append-icon="mdi-chevron-right"/>
      </v-list>
    </v-card>

    <template v-if="user?.role === UserRole.ADMIN">
      <div class="mt-12 mb-8 ml-4 ml-sm-0">{{ $t('settings.page.admin') }}</div>
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
import {useI18n} from "#i18n";
import {useUser} from "~/composables/states";
import {logout} from "~/utils/api";
import {UserRole} from "~/utils/model";
import MainContainer from "~/components/MainContainer.vue";

const {t} = useI18n();
const user = useUser();

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
