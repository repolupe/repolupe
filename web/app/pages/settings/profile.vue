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
          <td><v-btn @click="showFullNameDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        <tr>
          <td>{{ $t('settings.profile.firstName') }}</td>
          <td>{{ user.first_name ?? '-' }}</td>
          <td><v-btn @click="showFirstNameDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        <tr>
          <td>{{ $t('settings.profile.about') }}</td>
          <td class="py-2" style="white-space: pre-line">{{ user.about || '-' }}</td>
          <td><v-btn @click="showAboutMeDialog" icon="mdi-pencil" variant="text"/></td>
        </tr>
        </tbody>
      </v-table>
    </v-card>

    <FullNameDialog ref="full-name-dialog" v-model="dialogFullName" :loading="loading" @submit="updateFullName"/>
    <FirstNameDialog ref="first-name-dialog" v-model="dialogFirstName" :loading="loading" @submit="updateFirstName"/>
    <AboutMeDialog ref="about-me-dialog" v-model="dialogAbout" :loading="loading" @submit="updateAbout"/>
  </MainContainer>
</template>

<script setup lang="ts">
import {ref, useTemplateRef} from "vue";
import {useI18n} from "#i18n";
import {refreshUser, useUser} from "~/composables/states";
import {errorMessage, updateMyProfile, type UpdateProfilePayload} from "~/utils/api";
import {showSnackbar} from "~/utils/utils";
import MainContainer from "~/components/MainContainer.vue";
import AboutMeDialog from "~/components/settings/AboutMeDialog.vue";
import FirstNameDialog from "~/components/settings/FirstNameDialog.vue";
import FullNameDialog from "~/components/settings/FullNameDialog.vue";

const fullNameDialog = useTemplateRef<InstanceType<typeof FullNameDialog>>('full-name-dialog');
const firstNameDialog = useTemplateRef<InstanceType<typeof FirstNameDialog>>('first-name-dialog');
const aboutMeDialog = useTemplateRef<InstanceType<typeof AboutMeDialog>>('about-me-dialog');

const {t} = useI18n();

const user = useUser();

const loading = ref(false);
const dialogFullName = ref(false);
const dialogFirstName = ref(false);
const dialogAbout = ref(false);

const showFullNameDialog = () => {
  fullNameDialog.value!.load(user.value!.full_name, user.value!.first_name, user.value!.about);
  dialogFullName.value = true;
}

const showFirstNameDialog = () => {
  firstNameDialog.value!.load(user.value!.full_name, user.value!.first_name, user.value!.about);
  dialogFirstName.value = true;
}

const showAboutMeDialog = () => {
  aboutMeDialog.value!.load(user.value!.full_name, user.value!.first_name, user.value!.about);
  dialogAbout.value = true;
}

const updateFullName = async (data: UpdateProfilePayload) => {
  if (await updateProfile(data, t('settings.profile.page.fullNameSaved'), (error) => t('settings.profile.page.fullNameSaveFailed', {error}))) {
    dialogFullName.value = false;
  }
}

const updateFirstName = async (data: UpdateProfilePayload) => {
  if (await updateProfile(data, t('settings.profile.page.firstNameSaved'), (error) => t('settings.profile.page.firstNameSaveFailed', {error}))) {
    dialogFirstName.value = false;
  }
}

const updateAbout = async (data: UpdateProfilePayload) => {
  if (await updateProfile(data, t('settings.profile.page.aboutSaved'), (error) => t('settings.profile.page.aboutSaveFailed', {error}))) {
    dialogAbout.value = false;
  }
}

// Saves the profile, returns whether that succeeded.
const updateProfile = async (data: UpdateProfilePayload, saved: string, failed: (error: string) => string): Promise<boolean> => {
  loading.value = true;
  try {
    await updateMyProfile(data);
    await refreshUser();
    showSnackbar(saved);
    return true;
  } catch (e) {
    showSnackbar(failed(errorMessage(e)));
    return false;
  } finally {
    loading.value = false;
  }
}
</script>
