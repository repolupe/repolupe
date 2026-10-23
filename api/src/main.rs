//! The Repolupe server, configured from environment variables (see `.env.example.full`).

use axum::http::Request;
use repolupe::{Config, DatabaseConfig, Repolupe, RuntimeConfig, env};
use tower_http::trace::TraceLayer;
use tracing::{Level, info_span};

/// Prepares the configured OCR engine (see [`repolupe::prepare_ocr`]) and exits instead of
/// serving, e.g. to download the PaddleOCR models when building the Docker image.
const PREPARE_OCR: &str = "--prepare-ocr";

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt().with_max_level(Level::INFO).init();

    if let Some(arg) = std::env::args().nth(1) {
        if arg != PREPARE_OCR {
            panic!("Unknown argument {arg:?}, the only one is {PREPARE_OCR}");
        }
        let runtime = RuntimeConfig::from_env().unwrap_or_else(|e| panic!("{e}"));
        let Some(ocr) = runtime.ocr() else {
            panic!("{PREPARE_OCR} needs {} to be set", env::OCR_ENGINE);
        };
        repolupe::prepare_ocr(&ocr)
            .await
            .unwrap_or_else(|e| panic!("Failed to prepare OCR: {e}"));
        tracing::info!("OCR is ready");
        return;
    }

    let config = Config::from_env().unwrap_or_else(|e| panic!("{e}"));
    let db = DatabaseConfig::from_env()
        .connect()
        .await
        .unwrap_or_else(|e| panic!("{e}"));
    let repolupe = Repolupe::new(config, db)
        .await
        .unwrap_or_else(|e| panic!("Failed to start: {e}"));

    let app = repolupe
        .router()
        .layer(
            TraceLayer::new_for_http().make_span_with(|request: &Request<_>| {
                info_span!(
                    "http",
                    method = ?request.method(),
                    path = request.uri().to_string(),
                )
            }),
        );

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    tracing::info!("Listening on {}", listener.local_addr().unwrap());
    axum::serve(listener, app)
        .with_graceful_shutdown(async move {
            shutdown_signal().await;
            tracing::info!("Shutting down");
            // Finishes the live answers first, so their streams end and connections can close.
            repolupe.shutdown().await;
        })
        .await
        .unwrap();
}

/// Ctrl+C, or SIGTERM (sent by `docker stop`).
async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("Failed to listen for Ctrl+C");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("Failed to listen for SIGTERM")
            .recv()
            .await;
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {}
        _ = terminate => {}
    }
}
