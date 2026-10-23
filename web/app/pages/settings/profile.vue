<template>
  <MainContainer :title="$t('settings.profile.title')" :parents="[{title: $t('settings.title'), to: '/settings'}]">
    <template v-slot:meta>
      <p class="text-medium-emphasis">
        {{ $t('settings.profile.page.description') }}
      </p>
    </template>

    <v-card v-if="user">
      <v-table>
        <tbody>
        <tr>
          <td>{{ $t('settings.profile.fullName') }}</td>
          <td>{{ user.full_name ?? '-' }}</td>
          <td><v-btn @click="showProfileDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        <tr>
          <td>{{ $t('settings.profile.firstName') }}</td>
          <td>{{ user.first_name ?? '-' }}</td>
          <td><v-btn @click="showProfileDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        <tr>
          <td>{{ $t('settings.profile.about') }}</td>
          <td class="py-2" style="white-space: pre-line">{{ user.about || '-' }}</td>
          <td><v-btn @click="showProfileDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        </tbody>
      </v-table>
    </v-card>

    <ProfileDialog ref="profile-dialog" v-model="dialogProfile" :loading="loading" @submit="updateProfile"/>
  </MainContainer>
</template>

<script setup lang="ts">
import {ref, useTemplateRef} from "vue";
import {useI18n} from "#i18n";
import {refreshUser, useUser} from "~/composables/states";
import {errorMessage, updateMyProfile, type UpdateProfilePayload} from "~/utils/api";
import {showSnackbar} from "~/utils/utils";
import MainContainer from "~/components/MainContainer.vue";
import ProfileDialog from "~/components/settings/ProfileDialog.vue";

const profileDialog = useTemplateRef<InstanceType<typeof ProfileDialog>>('profile-dialog');

const {t} = useI18n();

const user = useUser();

const loading = ref(false);
const dialogProfile = ref(false);

const showProfileDialog = () => {
  profileDialog.value!.load(user.value!.full_name, user.value!.first_name, user.value!.about);
  dialogProfile.value = true;
}

const updateProfile = async (data: UpdateProfilePayload) => {
  loading.value = true;
  try {
    await updateMyProfile(data);
    dialogProfile.value = false;
    await refreshUser();
    showSnackbar(t('settings.profile.page.updated'));
  } catch (e) {
    showSnackbar(t('settings.profile.page.saveFailed', {error: errorMessage(e)}));
  } finally {
    loading.value = false;
  }
}
</script>
