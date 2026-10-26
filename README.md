# Repolupe

[![CI][ci-badge]][ci-workflow]
[![Docker][docker-badge]][docker-image]
[![License][license-badge]][license]

[ci-badge]: https://github.com/repolupe/repolupe/actions/workflows/ci.yml/badge.svg
[ci-workflow]: https://github.com/repolupe/repolupe/actions/workflows/ci.yml
[docker-badge]: https://img.shields.io/badge/docker-ghcr.io%2Frepolupe%2Frepolupe-blue?logo=docker&logoColor=white
[docker-image]: https://github.com/repolupe/repolupe/pkgs/container/repolupe
[license-badge]: https://img.shields.io/badge/license-Apache%202.0-blue.svg
[license]: LICENSE

[Homepage][homepage] • [Demo][demo] • [App Store][app store] • [Google Play][play store]

[homepage]: https://repolupe.com
[demo]: https://demo.repolupe.com
[app store]: https://apps.apple.com/app/id6823998189
[play store]: https://play.google.com/store/apps/details?id=com.repolupe.app

Chat with your private knowledge. Repolupe turns any git repository into a knowledge base you can talk to.
Your documents stay in your repositories, on your servers, under your control.

- [About](#about)
- [Features](#features)
- [Download](#download)
- [Setup](#setup)
  - [Docker](#docker)
  - [Docker Compose](#docker-compose)
  - [Updating](#updating)
  - [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## About

Repolupe is a self-hosted server that mirrors your git repositories and lets an LLM read them while it answers your
questions. Every answer links to the documents it came from. If you allow it, the assistant also files new documents
and updates your notes by proposing commits that you review before they are pushed.

A single instance connects your git servers to the LLM providers of your choice and serves the web app as well as the
Android and iOS apps.

## Features

- **Any git server:** GitHub, GitLab, Forgejo or your own server. Large files in Git LFS work too. Repositories can
  also live only on the Repolupe server.
- **AI-powered chat:** Ask questions in plain language. The assistant searches and reads your files and answers with
  the documents it used. Use Anthropic or any OpenAI-compatible API, including local models.
- **Read only or write:** For each repository, and for each person you share it with, decide whether the assistant
  only answers or also proposes commits.
- **Built-in OCR:** Scanned PDFs become searchable text with Tesseract or PaddleOCR, or with Mistral OCR.
- **Tiny footprint:** One small binary with an embedded SQLite database, using about 100 MB of RAM without local OCR.
- **Private by design:** No analytics, no tracking. With a local model and the built-in OCR, your documents and chats
  never leave your own infrastructure.

## Download

The server is published as a Docker image at `ghcr.io/repolupe/repolupe`, see [Setup](#setup).

| Web                     | Android                   | iOS                    |
|-------------------------|---------------------------|------------------------|
| Served by your instance | [Google Play][play store] | [App Store][app store] |

The mobile apps connect to your instance, or run Repolupe locally on the device.

## Setup

### Docker

1. Create a key. It encrypts the access tokens of your repositories and your LLM API keys, so keep it safe:

   ```bash
   echo "TOKEN_ENCRYPTION_KEY=$(openssl rand -hex 32)" > .env
   ```

2. Start the container. The database and the mirrored repositories are stored in the volume:

   ```bash
   docker run -d --name repolupe --env-file .env \
       -p 3000:3000 -v repolupe-data:/data \
       --restart unless-stopped ghcr.io/repolupe/repolupe
   ```

3. Open Repolupe on port `3000` and log in as `admin` with the password `repolupe123` (or `ADMIN_PASSWORD` if set),
   which has to be changed on the first login. Repositories, LLM providers and models are set up in the UI.

### Docker Compose

Create the key as above, then start the service with the [docker-compose.yml](docker-compose.yml) of this repository:

```bash
docker compose up -d
```

### Updating

```bash
docker compose pull && docker compose up -d
```

The image tag `latest` is the latest release. To pin a version, use a release (e.g. `0.1.0`) instead, or `main` for the
latest build of the main branch.

### Configuration

All environment variables are documented in [.env.example.full](.env.example.full), for example `OCR_ENGINE`
(`none`, `tesseract`, `paddle` or `mistral`) and `INSTANCE_NAME`. Changing `TOKEN_ENCRYPTION_KEY` later makes the
stored tokens unreadable, so they have to be entered again.

## How It Works

Repolupe mirrors each registered repository as a bare git repository and syncs it in the background. Documents such as
PDFs are converted to Markdown, with OCR for scanned pages. When you ask a question, the model reads a pinned commit of
the repository through tools (listing, searching and reading files) and streams its answer. In write mode, its changes
become proposed commits, which are pushed to the repository once you apply them.

The project consists of three parts:

| Directory      | Description                                                                                  |
|----------------|----------------------------------------------------------------------------------------------|
| [api](api)     | The server in Rust (axum, SQLite), also usable as a library                                  |
| [web](web)     | The web app in Nuxt and Vuetify, served by the server                                        |
| [app](app)     | The Flutter app for Android and iOS, talking to the server or running it in-process via Rust |

## Development

Install [Rust](https://www.rust-lang.org/tools/install), [Node.js](https://nodejs.org) and, for the app,
[fvm](https://fvm.app) (see the [required Flutter version](app/.fvmrc)). The default feature `local-ocr` needs Tesseract
and Leptonica (`brew install tesseract`).

**API** (`api/`)

```bash
cp ../.env.example ../.env   # set TOKEN_ENCRYPTION_KEY
set -a; source ../.env; set +a
cargo run
cargo test
```

**Web** (`web/`, with the API running on port `3000`)

```bash
npm install
npm run dev    # http://localhost:3001
npm test
```

**App** (`app/`)

```bash
fvm flutter pub get
fvm flutter run
fvm flutter test
```

See [CLAUDE.md](CLAUDE.md) for the architecture, conventions and code generation steps.

## Contributing

Contributions are welcome.

- **Bug fixes:** If you find a bug, please create a pull request with a clear description of the issue and the fix.
- **Improvements:** Have an idea? Please [open an issue](https://github.com/repolupe/repolupe/issues) first to discuss it.
- **Translations:** The texts are in [web/i18n/locales](web/i18n/locales) (shared with the app) and
  [app/assets/i18n](app/assets/i18n) (app only). Every locale has the same keys in the same order, checked by
  `npm run i18n:check`.

## License

Repolupe is licensed under the [Apache License 2.0](LICENSE).
