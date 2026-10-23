<template>
  <MainContainer :title="$t('admin.config.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <template v-slot:meta>
      <p class="text-medium-emphasis">
        {{ $t('admin.config.page.stored') }}
      </p>
      <i18n-t scope="global" keypath="admin.config.page.recommendEnv" tag="p" class="mt-2 text-medium-emphasis">
        <template v-slot:envVars>
          <b>{{ $t('admin.config.page.envVars') }}</b>
        </template>
      </i18n-t>
      <p class="mt-2 text-medium-emphasis">
        {{ $t('admin.config.page.ocrHint') }}
      </p>
    </template>

    <v-card>
      <v-card-text class="pb-0">
        <v-data-table
            :loading="fetching"
            :headers="[
                { title: $t('admin.config.page.key'), key: 'key', sortable: true },
                { title: $t('admin.config.page.env'), key: 'env', sortable: false },
                { title: $t('admin.config.page.override'), key: 'override', sortable: false },
                { title: $t('common.actions'), key: 'actions', sortable: false, width: 150 },
            ]"
            :items="entries"
            :items-per-page="-1"
            hide-default-footer
            :loading-text="$t('common.loading')"
            :no-data-text="$t('admin.config.page.noConfig')"
        >
          <template v-slot:item.key="{ item }">
            <code>{{ item.key }}</code>
          </template>

          <template v-slot:item.env="{ item }">
            <!-- struck through when not in effect -->
            <span v-if="item.env === null" class="text-disabled font-italic">{{ $t('admin.config.page.notSet') }}</span>
            <span v-else :class="{'text-decoration-line-through text-medium-emphasis': item.override !== null}">
              {{ item.env }}
            </span>
          </template>

          <template v-slot:item.override="{ item }">
            <span v-if="item.override !== null" class="font-weight-bold">{{ item.override }}</span>
            <span v-else-if="item.runtime" class="text-medium-emphasis">–</span>
            <span v-else class="text-disabled">{{ $t('admin.config.page.envOnly') }}</span>
          </template>

          <template v-slot:item.actions="{ item }">
            <template v-if="item.runtime">
              <v-btn @click="showOverrideDialog(item)" icon="mdi-pencil" variant="text" v-tooltip="$t('admin.config.overrideAction')" />
              <v-btn v-if="item.override !== null" @click="doSetOverride(item.key, null)" icon="mdi-backup-restore"
                     variant="text" :disabled="loading" v-tooltip="$t('admin.config.page.useEnv')" />
            </template>
          </template>
        </v-data-table>
      </v-card-text>
    </v-card>

    <OverrideDialog ref="override-dialog" v-model="dialogOverride" :loading="loading"
                    :config-key="selectedEntry?.key ?? ''" :env="selectedEntry?.env ?? ''"
                    @submit="value => doSetOverride(selectedEntry!.key, value)" />
  </MainContainer>
</template>

<script setup lang="ts">
import {onMounted, ref, useTemplateRef} from "vue";
import {useI18n} from "#i18n";
import type {ConfigEntryDto} from "~/utils/model";
import {showSnackbar} from "~/utils/utils";
import {errorMessage, getConfig, setConfigOverrides} from "~/utils/api";
import {useInstanceName} from "~/composables/states";
import MainContainer from "~/components/MainContainer.vue";
import OverrideDialog from "~/components/admin-config/OverrideDialog.vue";

const {t} = useI18n();

const overrideDialog = useTemplateRef<InstanceType<typeof OverrideDialog>>('override-dialog');

const instanceName = useInstanceName();

const fetching = ref(true);
const loading = ref(false);
const entries = ref<ConfigEntryDto[]>([]);
const selectedEntry = ref<ConfigEntryDto | null>(null);

const dialogOverride = ref(false);

const fetchData = async () => {
  try {
    fetching.value = true;
    entries.value = await getConfig();
  } catch (e) {
    showSnackbar(t('admin.config.page.loadFailed', {error: errorMessage(e)}));
  } finally {
    fetching.value = false;
  }
}

const showOverrideDialog = (entry: ConfigEntryDto) => {
  selectedEntry.value = entry;
  overrideDialog.value!.reset(entry.override);
  dialogOverride.value = true;
}

/** `null` removes the override of `key`. The API replaces all overrides, so the others are sent too. */
const doSetOverride = async (key: string, value: string | null) => {
  const overrides: Record<string, string> = {};
  for (const entry of entries.value) {
    if (entry.override !== null && entry.key !== key) {
      overrides[entry.key] = entry.override;
    }
  }
  if (value !== null) {
    overrides[key] = value;
  }

  loading.value = true;
  try {
    entries.value = await setConfigOverrides(overrides);
    dialogOverride.value = false;
    const name = entries.value.find(e => e.key === 'INSTANCE_NAME');
    if (name) {
      instanceName.value = name.override ?? name.env;
    }
    showSnackbar(t('admin.config.page.updated'));
  } catch (e) {
    showSnackbar(t('admin.config.page.saveFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}

onMounted(async () => {
  await fetchData();
});
</script>
