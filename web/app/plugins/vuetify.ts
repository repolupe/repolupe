import '@mdi/font/css/materialdesignicons.css'

import 'vuetify/styles'
import {watch} from "vue";
import {createVuetify} from 'vuetify'
import {de, en} from 'vuetify/locale'
import {defineNuxtPlugin} from "#imports";

export default defineNuxtPlugin({
    name: 'vuetify',
    dependsOn: ['i18n:plugin'],
    setup(app) {
        const vuetify = createVuetify({
            theme: {
                themes: {
                    light: {
                        dark: false,
                        colors: {
                            primary: '#00002b',
                            secondary: '#f0f2f5'
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
