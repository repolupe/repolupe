import {watch} from "vue";
import {defineNuxtPlugin, useHead} from "#app";
import {useUser} from "~/composables/states";
import {initI18n, setFormatLocale} from "~/utils/i18n";

/**
 * Shows the UI in the user's language (`UserDto.locale`), else in the browser's, else in the default locale.
 * A tag matches a locale of nuxt.config.ts by its code (e.g. `de-CH` matches `de`); dates and numbers are formatted
 * with that tag, so they follow the texts around them.
 */
export default defineNuxtPlugin({
    name: 'locale',
    dependsOn: ['i18n:plugin'],
    async setup(nuxtApp) {
        const i18n = nuxtApp.$i18n;
        initI18n(i18n);
        const user = useUser();

        /** The locale of the first tag with one, and the tag to format with (e.g. `de-CH` for `de`). */
        const resolve = (tags: readonly string[]) => {
            const codes = i18n.locales.value.map(l => l.code);
            for (const tag of tags) {
                const language = tag.toLowerCase().split('-')[0];
                const code = codes.find(c => c === language);
                if (code) {
                    return {code, tag};
                }
            }
            const code = i18n.defaultLocale;
            return {code, tag: i18n.locales.value.find(l => l.code === code)?.language ?? code};
        };

        const apply = async (locale: string | null | undefined) => {
            const {code, tag} = resolve(locale ? [locale] : navigator.languages);
            await i18n.setLocale(code);
            setFormatLocale(tag);
        };

        // the browser's language for the first page, before the user is loaded
        await apply(null);
        watch(() => user.value?.locale, apply);

        useHead({
            htmlAttrs: {lang: () => i18n.localeProperties.value.language},
        });
    },
});
