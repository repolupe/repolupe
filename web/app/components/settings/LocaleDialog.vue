<template>
  <GenericSaveDialog :title="$t('settings.preferences.localeDialog.title')" v-model="dialog" :loading="props.loading" @submit="submit">
    <div class="text-body-2 text-medium-emphasis mb-4">
      {{ $t('settings.preferences.localeDialog.description') }}
    </div>
    <v-combobox v-model="locale" :items="locales" :label="$t('settings.preferences.localeDialog.label')"
                prepend-icon="mdi-web" :disabled="loading" :return-object="false" />
  </GenericSaveDialog>
</template>

<script setup lang="ts">
import {computed, ref} from "vue";
import {trimmedOrNull} from "~/utils/utils";
import {useI18n} from "#i18n";
import GenericSaveDialog from "~/components/dialogs/GenericSaveDialog.vue";

const LOCALES = [
  'en-US',
  'en-GB',
  'de-DE',
  'de-CH',
  'fr-FR',
  'es-ES',
  'it-IT',
  'nl-NL',
  'pt-BR',
  'pl-PL',
  'sv-SE',
  'tr-TR',
  'ru-RU',
  'ja-JP',
  'ko-KR',
  'zh-CN',
  'zh-TW',
  'vi-VN',
];

/** The item for no locale of its own, i.e. the browser's languages. */
const BROWSER_DEFAULT = 'browser-default';

/** Chinese is named by its script, which tells the two apart better than the region. */
const NAMED_AS: Record<string, string> = {'zh-CN': 'zh-Hans', 'zh-TW': 'zh-Hant'};

const {t, locale: uiLocale} = useI18n();

const browserLocale = navigator.language;

/** The browser's languages first, since the user likely wants one of them, then the others; invalid tags are skipped. */
const TAGS = [...new Set([
  ...navigator.languages.flatMap(tag => {
    try {
      return Intl.getCanonicalLocales(tag);
    } catch {
      return [];
    }
  }),
  ...LOCALES,
])];

/** The browser default, then the tags with their names in the UI language, e.g. "German (Germany) - de-DE". */
const locales = computed(() => {
  const names = new Intl.DisplayNames([uiLocale.value], {type: 'language', languageDisplay: 'standard'});
  return [
    {title: t('settings.preferences.browserDefault', {locale: browserLocale}), value: BROWSER_DEFAULT},
    ...TAGS.map(tag => ({title: `${names.of(NAMED_AS[tag] ?? tag) ?? tag} - ${tag}`, value: tag})),
  ];
});

const props = defineProps<{
  modelValue: boolean,
  loading: boolean,
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: boolean): void,
  (e: 'submit', locale: string | null): void,
}>();

const dialog = computed({
  get: () => props.modelValue,
  set: (val: boolean) => emit('update:modelValue', val)
});

const locale = ref<string | null>(BROWSER_DEFAULT);

/** A cleared field means the browser default too. */
const submit = () => {
  const value = trimmedOrNull(locale.value);
  emit('submit', value === BROWSER_DEFAULT ? null : value);
}

defineExpose({
  load: (currentLocale: string | null) => {
    locale.value = currentLocale ?? BROWSER_DEFAULT;
  },
});
</script>
