<template>
  <v-dialog v-model="dialog" width="auto">
    <v-card width="500" :title="$t('repositories.shareDialog.title')">
      <template v-slot:text>
        <p class="mb-4">
          {{ $t('repositories.shareDialog.description') }}
        </p>
        <v-text-field v-model="name" @keydown.enter="submit" :label="$t('user.userNameOrEmail')"
                      prepend-icon="mdi-account" :disabled="props.loading" autofocus/>
      </template>

      <template v-slot:actions>
        <v-btn :text="$t('common.cancel')" @click="dialog = false"/>

        <v-btn @click="submit" color="primary" variant="elevated" :loading="props.loading"
               prepend-icon="mdi-share-variant" :text="$t('repositories.share')"/>
      </template>
    </v-card>
  </v-dialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {showSnackbar} from "~/utils/utils";
import {useI18n} from "#i18n";

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', userNameOrEmail: string): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const {t} = useI18n();

const name = ref('');

const submit = () => {
  const trimmed = name.value.trim();
  if (!trimmed) {
    showSnackbar(t('repositories.shareDialog.missing'));
    return;
  }
  emit('submit', trimmed);
}

defineExpose({
  reset: () => {
    name.value = '';
  },
});
</script>
