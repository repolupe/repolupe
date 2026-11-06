<template>
  <div class="fade-in d-flex flex-column align-center" :class="{'fade-in-hidden': !showLogo}">
    <v-img src="/logo-512.webp" :alt="$t('app.logoAlt')" width="80" height="80" class="flex-grow-0"/>
    <!-- the lines take the same cell, so the page does not jump when a long greeting is replaced -->
    <p class="hero-text text-h4 text-center mt-4 mb-12">
      <span class="hero-line hero-line-above" :class="{'hero-line-hidden': temporary}">{{ greeting }}</span>
      <span class="hero-line hero-line-below" :class="{'hero-line-hidden': !temporary}">{{ $t('chat.temporary') }}</span>
    </p>
  </div>
</template>

<script setup lang="ts">
import {computed, onBeforeUnmount, onMounted, ref} from "vue";
import {useI18n} from "#i18n";
import {useUser} from "~/composables/states";
import {dayTime, type DayTime} from "~/utils/utils";

defineProps<{
  /** Shows that the chat will be temporary instead of the greeting. */
  temporary: boolean,
}>();

const {t} = useI18n();
const user = useUser();

const DAY_TIME_GREETINGS: Record<DayTime, string> = {
  night: 'chat.startPage.greetingNight',
  morning: 'chat.startPage.greetingMorning',
  day: 'chat.startPage.greetingDay',
  evening: 'chat.startPage.greetingEvening',
};

/** By the time of day with the user's first name, if they gave one, else asks what they would like to know. */
const greeting = computed(() => {
  const name = user.value?.first_name;
  return name ? t(DAY_TIME_GREETINGS[dayTime(new Date())], {name}) : t('chat.startPage.greeting');
});

/** The logo and greeting fade in shortly after the page appears. */
const LOGO_DELAY_MS = 100;

const showLogo = ref(false);

let logoTimeout: ReturnType<typeof setTimeout> | undefined;

onMounted(() => logoTimeout = setTimeout(() => showLogo.value = true, LOGO_DELAY_MS));

onBeforeUnmount(() => clearTimeout(logoTimeout));
</script>

<style scoped>
.fade-in {
  transition: opacity 200ms, visibility 200ms;
}

.fade-in-hidden {
  opacity: 0;
  visibility: hidden;
}

.hero-text {
  display: grid;
}

.hero-line {
  grid-area: 1 / 1;
  transition: opacity 200ms 200ms, transform 200ms 200ms ease-out;
}

.hero-line-hidden {
  opacity: 0;
  visibility: hidden;
  transition: opacity 200ms, transform 200ms ease-in, visibility 0ms 200ms;
}

.hero-line-above.hero-line-hidden {
  transform: translateY(-12px);
}

.hero-line-below.hero-line-hidden {
  transform: translateY(12px);
}
</style>
