<template>
  <MainContainer :title="$t('admin.server.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <v-card>
      <v-list lines="two">
        <!-- tapping copies the value -->
        <v-list-item v-for="item in items" :key="item.title" :title="item.title" :prepend-icon="item.icon"
                     :disabled="!item.value" @click="copy(item.value!)">
          <v-list-item-subtitle>
            <v-progress-circular v-if="item.value === undefined && loading" indeterminate size="16" width="2"/>
            <template v-else>{{ item.value }}</template>
          </v-list-item-subtitle>
        </v-list-item>
      </v-list>
    </v-card>
  </MainContainer>
</template>

<script setup lang="ts">
import {computed, onMounted, ref} from "vue";
import {useI18n} from "#i18n";
import {errorMessage, getServer} from "~/utils/api";
import {type ServerDto} from "~/utils/model";
import {showSnackbar} from "~/utils/utils";
import MainContainer from "~/components/MainContainer.vue";

const {t} = useI18n();

const loading = ref(true);
const server = ref<ServerDto | null>(null);

// The server serves this app, so its base URL is the page's origin.
const items = computed(() => [
  {title: t('admin.server.page.baseUrl'), value: window.location.origin, icon: 'mdi-link'},
  {title: t('admin.server.page.version'), value: server.value?.version, icon: 'mdi-tag'},
]);

const copy = async (value: string) => {
  try {
    await navigator.clipboard.writeText(value);
    showSnackbar(t('admin.server.page.copied'));
  } catch {
    showSnackbar(t('admin.server.page.copyFailed'));
  }
}

onMounted(async () => {
  try {
    server.value = await getServer();
  } catch (e) {
    showSnackbar(t('admin.server.page.loadFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
});
</script>
