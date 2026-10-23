# Repolupe frontend

Nuxt 4 (SPA, `ssr: false`) + Vuetify 3, talking to the API in `../api` under `/api/v1`.

```bash
npm install
npm run dev        # http://localhost:3001, proxies /api/v1 to the API on http://localhost:3000
npm run typecheck
npm test           # vitest: test/unit/ in Node, test/nuxt/ in the Nuxt runtime
npm run generate   # static build in .output/public
```

`VITE_DEMO=true npm run dev` (or `generate`) builds a demo that runs without the API: requests are answered in
memory by `app/utils/demo.ts`, answers in chats with repositories show the sample scan (the others get a
generic greeting), and the settings are disabled.

Start the API first (`docker compose up` from the repo root, or `cargo run` in `api/` to run the current source) and log in with
the user `admin` and `ADMIN_PASSWORD` (default `repolupe123`, to be changed on the first login). The session is the API's HttpOnly `session` cookie, which is marked `Secure`:
browsers accept it on `http://localhost`, but not on other plain-http hosts.
