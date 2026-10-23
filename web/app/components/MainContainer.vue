<template>
  <div id="main-container-wrapper" style="padding: 30px 30px 100px 30px; min-height: 100vh">

    <div id="main-container-top-spacer" style="display: none; height: 30px"></div>

    <div style="margin: auto; max-width: 1200px">
      <!-- title -->
      <div class="mb-8 ml-4 ml-sm-0">
        <span>
          <template v-for="parent in props.parents" :key="parent.to">
            <NuxtLink :to="parent.to" class="title-parent">{{ parent.title }}</NuxtLink>
            <span class="mx-2 text-medium-emphasis">/</span>
          </template>
          <span>{{ displayTitle }}</span>
        </span>
      </div>

      <div style="margin: auto; display: flex; align-items: flex-start">

        <!-- body -->
        <div style="flex: 1; min-width: 0">
          <slot></slot>

          <v-card class="mt-12 hidden-md-and-up" v-if="$slots.meta">
            <v-card-text>
              <slot name="meta"></slot>
            </v-card-text>
          </v-card>
        </div>

        <!-- meta -->
        <v-card class="ml-12 hidden-sm-and-down" style="width: 300px; flex-shrink: 0" v-if="$slots.meta">
          <v-card-text>
            <slot name="meta"></slot>
          </v-card-text>
        </v-card>
      </div>
    </div>

  </div>
</template>

<script lang="ts" setup>
import {computed} from "vue";
import {NuxtLink} from "#components";
import {useI18n} from "#i18n";

const {t} = useI18n();

const props = defineProps<{
  title: string,
  // Pages above this one, shown before the title like a directory path (e.g. "Settings / Users").
  parents?: { title: string, to: string }[],
}>();

// After the breadcrumb, a title like "user/repo" would read as part of the path, so it is quoted.
const displayTitle = computed(() =>
    props.parents?.length && props.title.includes('/') ? t('app.mainContainer.quotedTitle', {title: props.title}) : props.title);

</script>

<style scoped>
.title-parent {
  color: inherit;
  text-decoration: none;
  opacity: 0.6;
}

.title-parent:hover {
  opacity: 1;
}

@media screen and (min-width: 1600px) {
  #main-container-top-spacer {
    display: block !important;
  }
}

@media screen and (max-width: 600px) {
  #main-container-wrapper {
    padding: 30px 0 100px 0 !important;
  }
}
</style>
