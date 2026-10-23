# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Repolupe answers questions about git repositories with an LLM. The server mirrors registered repositories (remote ones, or local ones that exist only on the server) as bare git repos, and the model reads them through tools while answering in chats.

- `api/`: Rust crate `repolupe` (axum + sqlx/SQLite), a library other apps embed plus the server binary.
- `web/`: Nuxt 4 + Vuetify 3 SPA, served by the server from `FRONTEND_DIR` in the Docker image.
- `app/`: Flutter app (iOS, Android) that talks to a server, or runs Repolupe in-process as a local instance, through the Rust crate `app/rust`.

All configuration is in `.env.example.full`. LLM providers and models are configured at runtime by an admin, not via env.

## Commands

```bash
# api/
cargo build
cargo test                      # unit + integration tests
cargo test <name>               # single test
cargo test --test integration   # only tests/integration/
cargo clippy --all-targets
cargo fmt

# web/ (API must run on :3000)
npm run dev                     # :3001, proxies /api/v1
npm run typecheck
npm test
npm run i18n:check

# app/ (Flutter pinned in app/.fvmrc, always run it through fvm)
fvm flutter test
fvm flutter analyze
flutter_rust_bridge_codegen generate && fvm dart run build_runner build   # after changing app/rust/src/api or api/src/dto
fvm dart run slang              # after changing app/assets/i18n
fvm dart tool/import_web_i18n.dart   # after changing web/i18n/locales, then run slang
cd rust && cargo test
```

- `cargo run` doesn't load `.env`; export it first (`set -a; source ../.env; set +a`). `TOKEN_ENCRYPTION_KEY` is required, `DATABASE_URL` defaults to `sqlite:rp.db`.
- The default feature `local-ocr` needs Tesseract and Leptonica via pkg-config (`brew install tesseract`). Without it (`--no-default-features`, used for mobile) only Mistral OCR is available.
- `ort` and `rig-core` are pinned on purpose; newer releases break the build or the API.
- Git runs in-process with gitoxide. Only the tests use the `git` CLI.

## sqlx / SQLite

- Use only the checked macros (`query!`, `query_as!`, `query_scalar!`). After changing a query, regenerate and commit `.sqlx/` (the Docker build uses `SQLX_OFFLINE=true`):
  ```bash
  export DATABASE_URL=sqlite:target/sqlx.db
  sqlx database reset -y
  cargo sqlx prepare -- --all-targets
  ```
- Never edit an existing migration (sqlx checks their checksums, and released databases already ran them). Every schema change goes into a new file `migrations/<YYYYMMDDHHMMSS>_<name>.sql`. Migrations run on startup. SQLite's `ALTER TABLE` can't change constraints, so a new enum value (a changed `CHECK`) means rebuilding the table: create the new one, copy the rows, drop the old one, rename, then recreate the indexes. With foreign keys on, dropping a referenced table runs its `ON DELETE CASCADE`s, and `PRAGMA foreign_keys` has no effect inside the transaction sqlx wraps each migration in. Such a migration needs `-- no-transaction` on its first line and its own `PRAGMA foreign_keys = OFF`, `BEGIN`/`COMMIT` and `PRAGMA foreign_key_check`.
- Columns other than bool/i32/i64/String/Vec<u8> need type overrides: `id AS "id: Uuid"` (16-byte BLOB), `created_at AS "created_at: DateTime<Utc>"`, enums (`TEXT` + `CHECK`, `#[derive(sqlx::Type)]` with `SCREAMING_SNAKE_CASE`), JSON, decimals (`sqlx::types::Text<Decimal>`), and expressions (`EXISTS (...) AS "exists!: bool"`).
- Timestamps compare as text, so bind them from Rust (`let now = Utc::now();`, since the macros borrow their arguments). Never use SQL's `now()`.
- SQLite has no arrays: pass lists as `Json(ids)` and read them with `json_each` (`unhex(value, '-')` for UUIDs).
- Write transactions start with `repository::begin_write` (`BEGIN IMMEDIATE`).
- Integration tests (`tests/integration/`, `#[sqlx::test]`) use only the public API. `support.rs` has `TestApp` and `MockLlm`.

## Architecture (`api/src/`)

- `controller/` holds the handlers; all routes are in `lib.rs`, grouped into public, authenticated and admin. `dto/` holds the public request/response types, which the app's Rust client uses too: plain data, both `Serialize` and `Deserialize`, decimals as strings, counts as `i64`. `service/` holds the logic and background tasks, `repository/` all SQL.
- Queries enforce ownership by `user_id`, so a foreign id is `NotFound`. Repositories can be shared (`repository_users`): reads match owned or shared repositories, writes only owned ones (`FORBIDDEN` otherwise).
- The library's public API is `Repolupe` (`new`, `router`, `shutdown`), `dto` and `env`. It reads the environment only in the `from_env` constructors in `config/env.rs` (add new variables there and to `.env.example.full`). It never installs tracing, binds a port or panics; that belongs in `main.rs`.
- `RuntimeConfig` (`config/runtime.rs`) holds the settings admins can change without a restart (overrides in the `config` table).

### Conventions

- Handlers return `Result<_, AppError>`, which is rendered as `{code, message}` with a stable `ErrorCode`. User-facing text must never leak internals.
- Use the extractors in `util/extract.rs`, not axum's.
- Use only GET and POST (`/update`, `/delete`, `/cancel` as sub-paths). Authenticated POSTs must be JSON or `application/octet-stream`; this is the CSRF protection.
- IDs are `Uuid::now_v7()`, and timestamps are set in Rust.
- Use `tokio::pin!`, not `std::pin::pin!`, because the flutter_rust_bridge codegen can't parse `super let`.
- Background tasks take a `CancellationToken` and return their `JoinHandle`. The server assumes a single API instance (in-memory generation registry, sync scheduler).

### Subsystems

- **Sync** (`service/sync.rs`): a background loop syncs due repositories. Mirrors are accessed only through `service/mirror/mod.rs` (`MirrorStore`, `Snapshot`); its `git/` and `lfs.rs` submodules are private so LFS pointers never leak out. Keep it that way.
- **Outbound HTTP**: build every client with `util::http::client_builder` (rustls). Requests to user-supplied URLs are SSRF-hardened (https only, public addresses via `util::ip::PublicResolver`); admin-owned repositories are exempt.
- **Secrets**: repository tokens and LLM API keys are AES-GCM encrypted with `TOKEN_ENCRYPTION_KEY`, using the row id as associated data.
- **Extraction** (`service/extraction.rs`): a background task converts documents (PDFs) to Markdown with xberg, one at a time. Results are stored by blob oid with an `extractor` id; bump `EXTRACTOR` when the xberg version or config changes.
- **Answers** (`service/generation.rs`, `answer.rs`): answers are generated in the background and streamed over SSE. `generation::finish` is the only place a message gets its final status. In the tool loop, keep `system` and `tools` unchanged and only append messages, because prompt caching and thinking blocks depend on that.
- **Tools** (`service/tools/`): one file per tool, registered in `service/tools/mod.rs`, all reading one pinned commit. `change_file`, `move_files` and `save_attachment` propose commits that the user pushes (`service/commit.rs`).
- **LLMs** (`service/llm/`): Anthropic and OpenAI-compatible streaming via `rig-core`, translated in `service/llm/convert.rs`. Provider-specific blocks pass through opaquely (`ProviderBlock`); don't model them.

## Frontend (`web/`)

- `imports.autoImport` is off: import explicitly from `vue`, `#app` and `#i18n`, never from `vue-router`.
- `utils/api.ts` wraps every endpoint and throws `ApiError`; branch on its `code`. `utils/model.ts` mirrors `api/src/dto/`, so update both sides together.
- Edits happen in dialogs built on `GenericSaveDialog`, `GenericDeleteDialog` or `GenericConfirmDialog`, with feedback via `showSnackbar`.
- All texts go in `i18n/locales/<code>.json`: camelCase keys grouped by feature, the same keys in the same order in every locale (checked by `npm run i18n:check`). Outside components use `t` from `utils/i18n.ts`, and format dates and numbers with `formatLocale()`.

## App (`app/`)

- State uses refena, models use dart_mappable. The app reaches the API only through `app/rust` (`repolupe_ffi`), bound with flutter_rust_bridge using native assets (`hook/build.dart`), pinned to the same exact version in `pubspec.yaml` and `rust/Cargo.toml`. `rust/rust-toolchain.toml` must pin an exact version.
- The bridge binds `crate::api` and `repolupe::dto`, so DTO changes need a regeneration. FRB's own build_runner run is off because it deletes other generated files; run `fvm dart run build_runner build` after the codegen.
- `Client` (`rust/src/api/client.rs`) sends every request through `Transport`: `Remote` (reqwest) or `Local` (the in-process router of a local instance, started in `api/local.rs`).
- All texts go in `assets/i18n/<code>/<namespace>.json` (slang, generated into `lib/gen/`), with the same key conventions as `web/`. `base` is generated from the web's locales by `tool/import_web_i18n.dart` (never edit it), texts only the app needs go in `flutter`.
- Tests call `initRustLib()` (`test/support/rust.dart`), because FRB's loader can't find the library outside an app bundle. Widget tests serve fake JSON from an HTTP server on loopback and use `tester.runAsync` so the requests can run.
