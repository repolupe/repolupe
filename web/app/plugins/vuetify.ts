import '@mdi/font/css/materialdesignicons.css'

import 'vuetify/styles'
import {watch} from "vue";
import {createVuetify} from 'vuetify'
import {de, en} from 'vuetify/locale'
import {defineNuxtPlugin} from "#imports";
import {readThemeMode} from "~/utils/theme";

export default defineNuxtPlugin({
    name: 'vuetify',
    dependsOn: ['i18n:plugin'],
    setup(app) {
        const vuetify = createVuetify({
            // secondary is the page background, navigation the drawer and app bar (with the white logo),
            // temporary the page background of a new temporary chat
            theme: {
                defaultTheme: readThemeMode(),
                themes: {
                    light: {
                        dark: false,
                        colors: {
                            primary: '#00002b',
                            secondary: '#f0f2f5',
                            navigation: '#00002b',
                            temporary: '#e4e3f7',
                        },
                    },
                    dark: {
                        dark: true,
                        colors: {
                            primary: '#bec2ff',
                            secondary: '#131318',
                            background: '#131318',
                            surface: '#1f1f25',
                            navigation: '#0c0c26',
                            temporary: '#211a33',
                        },
                    },
                },
            },
            // the texts of Vuetify's own components, one per locale in nuxt.config.ts
            locale: {
                messages: {de, en},
            },
        })
        app.vueApp.use(vuetify)
        watch(app.$i18n.locale, (locale) => {
            vuetify.locale.current.value = locale;
        }, {immediate: true})
        // for code outside of components, where useDisplay() is not available
        return {provide: {display: vuetify.display}}
    },
})
