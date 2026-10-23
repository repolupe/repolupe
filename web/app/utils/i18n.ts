import {ref} from "vue";
import type {NuxtApp} from "#app";

type Composer = NuxtApp['$i18n'];

let composer: Composer | null = null;

/** Called once by plugins/locale.ts, before any page or middleware runs. */
export function initI18n(i18n: Composer) {
    composer = i18n;
}

/**
 * `t` of the app's i18n instance, for code outside components (utils, composables, code after an `await`), where
 * `useI18n()` is not available. Called in a `computed` or a template, the result follows a locale switch.
 */
export const t = ((...args: unknown[]) => (composer!.t as (...args: unknown[]) => string)(...args)) as Composer['t'];

const format = ref<string | undefined>(undefined);

/** Set by plugins/locale.ts with the language tag the UI locale was chosen by. */
export function setFormatLocale(tag: string) {
    format.value = tag;
}

/**
 * The tag to format dates and numbers with (`Intl`, `toLocaleString`), e.g. `de-CH` while the UI is in `de`, so they
 * match the texts around them. Reactive, like {@link t}.
 */
export const formatLocale = () => format.value;
