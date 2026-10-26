<template>
  <GenericSaveDialog :title="$t('settings.account.emailDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <v-text-field v-model="email" @keydown.enter="submit" :label="$t('user.emailOptional')" type="email" :disabled="loading"
                  autocomplete="email" prepend-icon="mdi-email" class="mb-2" />
    <div class="text-caption text-medium-emphasis">
      {{ $t('settings.account.loginHint') }}
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

// Sent unchanged, since the API changes both together.
const userName = ref('');
const email = ref('');

const submit = () => {
  const trimmedEmail = email.value.trim();
  const error = userNameOrEmailError(userName.value, trimmedEmail);
  if (error) {
    showSnackbar(error);
    return;
  }

  emit('submit', {
    user_name: userName.value,
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
