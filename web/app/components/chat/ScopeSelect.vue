<template>
  <v-menu :close-on-content-click="false">
    <template v-slot:activator="{ props: menuProps }">
      <!-- only icons and the number of selected items, so the row of selects stays short -->
      <button v-bind="menuProps" v-ripple type="button" class="activator" :disabled="props.disabled"
              :title="props.title" :aria-label="props.title">
        <v-icon :icon="none ? props.noneIcon : props.icon" class="activator-icon"/>
        <span v-if="count !== null">{{ count }}</span>
      </button>
    </template>

    <v-list density="compact" min-width="220" max-width="360" max-height="440">
      <v-list-subheader>{{ props.header }}</v-list-subheader>
      <v-list-item :title="props.allTitle" role="menuitemcheckbox" :aria-checked="props.modelValue.all"
                   @click="emit('update:modelValue', {all: !props.modelValue.all, ids: []})">
        <template v-slot:prepend>
          <!-- the item toggles, the checkbox only shows it (like in v-select) -->
          <v-checkbox-btn :model-value="props.modelValue.all" :ripple="false" tabindex="-1" aria-hidden="true"
                          @click.prevent/>
        </template>
      </v-list-item>
      <v-divider class="my-1"/>
      <v-list-item v-for="item in props.items" :key="item.id" :title="item.title" :subtitle="item.subtitle"
                   role="menuitemcheckbox" :aria-checked="isSelected(item.id)" @click="toggle(item.id)">
        <template v-slot:prepend>
          <v-checkbox-btn :model-value="isSelected(item.id)" :ripple="false" tabindex="-1" aria-hidden="true"
                          @click.prevent/>
        </template>
      </v-list-item>
    </v-list>
  </v-menu>
</template>

<script setup lang="ts">
/** Selects all items (including ones added later) or some of them, e.g. the repositories of a new chat. */
import {computed} from "vue";

export interface Scope {
  all: boolean;
  /** Ignored if `all`. */
  ids: string[];
}

export interface ScopeItem {
  id: string;
  title: string;
  subtitle?: string;
}

const props = defineProps<{
  modelValue: Scope,
  items: ScopeItem[],
  /** What the items are, above them. */
  header: string,
  allTitle: string,
  /** With all or some items selected. */
  icon: string,
  /** With no item selected. */
  noneIcon: string,
  /** The tooltip and the accessible name, the selection in words. */
  title: string,
  disabled?: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: Scope): void,
}>();

const none = computed(() => !props.modelValue.all && props.modelValue.ids.length === 0);

/** Only with some items selected, the icon tells all from none. */
const count = computed(() => props.modelValue.all || none.value ? null : props.modelValue.ids.length);

const isSelected = (id: string) => !props.modelValue.all && props.modelValue.ids.includes(id);

/** Picking an item while all are selected selects only that one. */
const toggle = (id: string) => {
  const ids = props.modelValue.all ? [] : props.modelValue.ids;
  emit('update:modelValue', {all: false, ids: ids.includes(id) ? ids.filter(i => i !== id) : [...ids, id]});
};
</script>

<style scoped>
/* like the plain v-select of the model next to it */
.activator {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 6px;
  /* the icon starts where the button does, the padding only shows with the ripple and the focus outline */
  margin-left: -6px;
  border-radius: 4px;
  font-size: 1rem;
  color: inherit;
  cursor: pointer;
}

.activator:disabled {
  cursor: default;
  opacity: var(--v-disabled-opacity);
}

.activator:focus-visible {
  outline: 2px solid rgb(var(--v-theme-primary));
}

.activator-icon {
  flex-shrink: 0;
  opacity: var(--v-medium-emphasis-opacity);
}
</style>
