<template>
  <GenericDeleteDialog :title="$t('admin.users.deleteDialog.title')" v-model="dialog"
                       @delete="emit('delete')" :loading="props.loading" :verify="props.userName">
    {{ $t('admin.users.deleteDialog.intro') }}
    <br>
    <b>{{ props.userName }}</b>
    <br><br>
    {{ $t('admin.users.deleteDialog.consequences') }}
    <br>
  </GenericDeleteDialog>
</template>

<script lang="ts" setup>
import {computed} from "vue";
import GenericDeleteDialog from "~/components/dialogs/GenericDeleteDialog.vue";

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
  userName: string,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'delete'): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});
</script>
