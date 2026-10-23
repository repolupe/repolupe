# Builds the API and the frontend into one image. The API serves the frontend from FRONTEND_DIR.

FROM node:24-slim AS frontend

WORKDIR /app

# Install dependencies first so they are cached between source changes
COPY web/package.json web/package-lock.json ./
RUN npm ci --ignore-scripts

COPY web ./
RUN npm run generate

FROM rust:1.97.1 AS api

# Tesseract and Leptonica for OCR, linked by xberg via pkg-config
RUN apt-get update \
    && apt-get install -y --no-install-recommends libtesseract-dev libleptonica-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Compile dependencies first so they are cached between source changes
COPY api/Cargo.toml api/Cargo.lock ./
RUN mkdir src && echo 'fn main() { panic!("Dummy image called!") }' > ./src/main.rs
RUN cargo build --release

# Add source
COPY api/src ./src
COPY api/migrations ./migrations
COPY api/.sqlx ./.sqlx

# Break cargo cache
RUN touch ./src/main.rs

# Compile
ENV SQLX_OFFLINE=true
RUN cargo build --release

FROM debian:13-slim AS runtime-base

# Fonts for rendering PDF pages for OCR
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libtesseract5 tesseract-ocr-eng \
        fonts-liberation fonts-urw-base35 fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

ENV FRONTEND_DIR=/frontend
ENV DATABASE_URL=sqlite:///data/rp.db
ENV REPOS_DIR=/data/repos
ENV ATTACHMENTS_DIR=/data/attachments
ENV XBERG_CACHE_DIR=/data/cache

# Not in /data, since a volume there would hide the models.
ENV XBERG_OCR_MODEL_CACHE_DIR=/opt/paddle-models

FROM runtime-base AS ocr-models

COPY --from=api /app/target/release/repolupe /repolupe

# Downloads the PaddleOCR models for the default languages (PP-OCRv6 small, covering English,
# Latin languages and Chinese) by recognizing a sample scan. This reruns for every new binary, but
# the download is the same as long as xberg's version is, so the COPY below stays cached and
# the image keeps the same models layer.
RUN OCR_ENGINE=paddle /repolupe --prepare-ocr

FROM runtime-base AS runtime

COPY --from=ocr-models /opt/paddle-models /opt/paddle-models
COPY --from=api /app/target/release/repolupe /repolupe
COPY --from=frontend /app/.output/public /frontend

EXPOSE 3000
ENTRYPOINT ["/repolupe"]
