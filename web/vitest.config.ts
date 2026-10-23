import {defineVitestConfig} from '@nuxt/test-utils/config'

// Tests with the app's aliases (`~`) and Vite's asset imports: those in test/unit/ run in Node, those in test/nuxt/
// in the Nuxt runtime (happy-dom).
export default defineVitestConfig({
    test: {
        include: ['test/**/*.test.ts'],
    },
})
