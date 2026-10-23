//! The tokio runtime the crate runs its requests on.
//!
//! FRB runs async functions on its own executor, but reqwest's connections and the local
//! router (its handlers, timers, and the background tasks of a local instance) need a tokio
//! runtime, so all of that runs here and is only awaited from the caller's executor.

use std::future::Future;
use std::pin::Pin;
use std::sync::OnceLock;
use std::task::{Context, Poll};

use tokio::runtime::Runtime;
use tokio::task::JoinHandle;

use crate::api::error::ClientError;

/// The crate's runtime, created on first use.
pub fn runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .thread_name("repolupe")
            .build()
            .expect("failed to start the tokio runtime")
    })
}

/// Runs `future` on the crate's runtime and waits for it on any executor. Dropping the returned
/// future aborts the task, so cancelling a request on the caller's side cancels it here too.
pub(crate) async fn run<F, T>(future: F) -> Result<T, ClientError>
where
    F: Future<Output = Result<T, ClientError>> + Send + 'static,
    T: Send + 'static,
{
    match (AbortOnDrop(runtime().spawn(future))).await {
        Ok(result) => result,
        Err(error) => Err(ClientError::transport(&error)),
    }
}

struct AbortOnDrop<T>(JoinHandle<T>);

impl<T> Future for AbortOnDrop<T> {
    type Output = <JoinHandle<T> as Future>::Output;

    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        Pin::new(&mut self.0).poll(cx)
    }
}

impl<T> Drop for AbortOnDrop<T> {
    fn drop(&mut self) {
        self.0.abort();
    }
}
