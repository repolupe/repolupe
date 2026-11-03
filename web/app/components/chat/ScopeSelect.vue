<template>
  <v-menu v-if="props.variant === 'item' || !props.modelValue.all" :close-on-content-click="false"
          :submenu="props.variant === 'item'" :disabled="props.disabled">
    <template v-slot:activator="{ props: menuProps }">
      <v-list-item v-if="props.variant === 'item'" v-bind="menuProps" :prepend-icon="icon" :title="props.header"
                   append-icon="mdi-chevron-right" :disabled="props.disabled"/>
      <!-- the close button selects all items again -->
      <v-chip v-else v-bind="menuProps" :prepend-icon="icon" :title="props.header" closable :disabled="props.disabled"
              class="scope-chip" @click:close="emit('update:modelValue', {all: true, ids: []})">
        <span class="text-truncate">{{ props.summary }}</span>
      </v-chip>
    </template>

    <v-list density="compact" min-width="220" max-width="360" max-height="440">
      <!-- a submenu is next to its item, which already says what the items are -->
      <v-list-subheader v-if="props.variant === 'chip'">{{ props.header }}</v-list-subheader>
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
  /** The selection in words, on the chip. */
  summary: string,
  /**
   * `item` is an entry of the message input's menu that opens the items as a submenu. `chip` is shown next to that
   * menu only while not all items are selected, so the default takes no space.
   */
  variant: 'item' | 'chip',
  disabled?: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: Scope): void,
}>();

const icon = computed(() => !props.modelValue.all && props.modelValue.ids.length === 0 ? props.noneIcon : props.icon);

const isSelected = (id: string) => !props.modelValue.all && props.modelValue.ids.includes(id);

/** Picking an item while all are selected selects only that one. */
const toggle = (id: string) => {
  const ids = props.modelValue.all ? [] : props.modelValue.ids;
  emit('update:modelValue', {all: false, ids: ids.includes(id) ? ids.filter(i => i !== id) : [...ids, id]});
};
</script>

<style scoped>
.scope-chip {
  max-width: 220px;
}
</style>
