import vuetify, {transformAssetUrls} from 'vite-plugin-vuetify'

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
    compatibilityDate: '2025-07-15',
    ssr: false,
    devtools: {enabled: true},
    experimental: {
        // only used between the start page and a chat, see middleware/view-transition.global.ts
        viewTransition: true,
    },
    imports: {
        autoImport: false,
    },
    typescript: {
        tsConfig: {
            // typechecked like the app (test/nuxt/ already is)
            include: ['../test/unit/**/*'],
        },
    },
    modules: ['@nuxtjs/i18n'],

    // The URLs carry no locale: it follows the user's language, else the browser's, see plugins/locale.ts.
    i18n: {
        strategy: 'no_prefix',
        defaultLocale: 'en',
        locales: [
            {code: 'en', language: 'en-US', name: 'English', file: 'en.json'},
            {code: 'de', language: 'de-DE', name: 'Deutsch', file: 'de.json'},
        ],
        detectBrowserLanguage: false,
    },

    app: {
        head: {
            // replaced by the instance name once the app has loaded, see app.vue
            title: 'Repolupe',
            link: [
                {rel: 'apple-touch-icon', href: '/apple-touch-icon.png'},
            ],
        },
    },

    // The API listens on :3000 (see .env.example.full), so the dev server moves aside.
    devServer: {
        port: 3001,
    },

    nitro: {
        devProxy: {
            '/api/v1': {
                target: 'http://localhost:3000/api/v1',
            }
        }
    },

    // https://vuetifyjs.com/en/getting-started/installation/#using-nuxt-3
    build: {
        transpile: ['vuetify'],
    },
    vite: {
        build: {
            // keeps the flags as files, so a page loads only those it shows instead of all of them in its CSS
            assetsInlineLimit: (file: string) => file.includes('/flag-icons/') ? false : undefined,
        },
        plugins: [
            vuetify({autoImport: true}),
        ],
        vue: {
            template: {
                transformAssetUrls,
            },
        },
    },
})
