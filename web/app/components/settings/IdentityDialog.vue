<template>
  <GenericSaveDialog :title="$t('settings.account.identityDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-model="userName" @keydown.enter="submit" :label="$t('user.userName')" :disabled="loading"
                  autocomplete="username" prepend-icon="mdi-account" class="mb-2" />
    <v-text-field v-model="email" @keydown.enter="submit" :label="$t('user.emailOptional')" type="email" :disabled="loading"
                  autocomplete="email" prepend-icon="mdi-email" class="mb-2" />
    <div class="text-caption text-grey-darken-1">
      {{ $t('settings.account.identityDialog.loginHint') }}
    </div>
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {showSnackbar, userNameOrEmailError} from "~/utils/utils";
import type {UpdateIdentityPayload} from "~/utils/api";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', value: UpdateIdentityPayload): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const userName = ref('');
const email = ref('');

const submit = () => {
  const trimmedUserName = userName.value.trim();
  const trimmedEmail = email.value.trim();
  const error = userNameOrEmailError(trimmedUserName, trimmedEmail);
  if (error) {
    showSnackbar(error);
    return;
  }

  emit('submit', {
    user_name: trimmedUserName,
    email: trimmedEmail || null,
  });
}

defineExpose({
  load: (currentUserName: string, currentEmail: string | null) => {
    userName.value = currentUserName;
    email.value = currentEmail ?? '';
  },
});
</script>
