use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Allows `max_attempts` attempts per key per window, counted from the first attempt.
/// In-memory, so limits reset on restart and are not shared between instances.
pub(crate) struct RateLimiter {
    max_attempts: u32,
    window: Duration,
    state: Mutex<State>,
}

#[derive(Default)]
struct State {
    windows: HashMap<String, Window>,
    last_prune: Option<Instant>,
}

struct Window {
    started: Instant,
    attempts: u32,
}

impl RateLimiter {
    pub(crate) fn new(max_attempts: u32, window: Duration) -> Self {
        Self {
            max_attempts,
            window,
            state: Mutex::new(State::default()),
        }
    }

    /// Counts an attempt for `key`. Fails with the time until the next attempt is allowed
    /// if the limit is reached.
    pub(crate) fn try_attempt(&self, key: &str) -> Result<(), Duration> {
        self.try_attempt_at(key, Instant::now())
    }

    /// Forgets the attempts of `key`, e.g. after it succeeded.
    pub(crate) fn reset(&self, key: &str) {
        self.state.lock().unwrap().windows.remove(key);
    }

    fn try_attempt_at(&self, key: &str, now: Instant) -> Result<(), Duration> {
        let mut state = self.state.lock().unwrap();

        // At most once per window, so many distinct keys do not slow down every attempt.
        if state
            .last_prune
            .is_none_or(|at| now.duration_since(at) >= self.window)
        {
            state
                .windows
                .retain(|_, w| now.duration_since(w.started) < self.window);
            state.last_prune = Some(now);
        }

        let window = state.windows.entry(key.to_string()).or_insert(Window {
            started: now,
            attempts: 0,
        });
        let elapsed = now.duration_since(window.started);
        if elapsed >= self.window {
            window.started = now;
            window.attempts = 0;
        } else if window.attempts >= self.max_attempts {
            return Err(self.window - elapsed);
        }
        window.attempts += 1;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WINDOW: Duration = Duration::from_secs(60);

    #[test]
    fn limits_attempts_per_window() {
        let limiter = RateLimiter::new(2, WINDOW);
        let start = Instant::now();
        assert!(limiter.try_attempt_at("a", start).is_ok());
        assert!(limiter.try_attempt_at("a", start).is_ok());
        let wait = limiter
            .try_attempt_at("a", start + Duration::from_secs(10))
            .unwrap_err();
        assert_eq!(wait, Duration::from_secs(50));
        // Other keys are independent
        assert!(limiter.try_attempt_at("b", start).is_ok());
        // A new window starts after the old one passed
        assert!(limiter.try_attempt_at("a", start + WINDOW).is_ok());
    }

    #[test]
    fn reset_allows_attempts_again() {
        let limiter = RateLimiter::new(1, WINDOW);
        let start = Instant::now();
        assert!(limiter.try_attempt_at("a", start).is_ok());
        assert!(limiter.try_attempt_at("a", start).is_err());
        limiter.reset("a");
        assert!(limiter.try_attempt_at("a", start).is_ok());
    }

    #[test]
    fn prunes_expired_windows() {
        let limiter = RateLimiter::new(1, WINDOW);
        let start = Instant::now();
        assert!(limiter.try_attempt_at("a", start).is_ok());
        assert!(limiter.try_attempt_at("b", start + WINDOW).is_ok());
        let state = limiter.state.lock().unwrap();
        assert!(!state.windows.contains_key("a"));
        assert!(state.windows.contains_key("b"));
    }
}
