use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use uuid::Uuid;

/// Allows one action per key per interval. In-memory, so limits reset on restart
/// and are not shared between instances.
pub(crate) struct Throttle {
    interval: Duration,
    last: Mutex<HashMap<Uuid, Instant>>,
}

impl Throttle {
    pub(crate) fn new(interval: Duration) -> Self {
        Self {
            interval,
            last: Mutex::new(HashMap::new()),
        }
    }

    /// Returns `false` if `key` was acquired less than one interval ago.
    pub(crate) fn try_acquire(&self, key: Uuid) -> bool {
        let now = Instant::now();
        let mut last = self.last.lock().unwrap();
        last.retain(|_, at| now.duration_since(*at) < self.interval);
        if last.contains_key(&key) {
            return false;
        }
        last.insert(key, now);
        true
    }

    /// Undoes [`Self::try_acquire`] when the action did not happen.
    pub(crate) fn release(&self, key: Uuid) {
        self.last.lock().unwrap().remove(&key);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_once_per_interval() {
        let throttle = Throttle::new(Duration::from_secs(60));
        let a = Uuid::now_v7();
        let b = Uuid::now_v7();
        assert!(throttle.try_acquire(a));
        assert!(!throttle.try_acquire(a));
        assert!(throttle.try_acquire(b));
        throttle.release(a);
        assert!(throttle.try_acquire(a));
    }

    #[test]
    fn expires_after_interval() {
        let throttle = Throttle::new(Duration::ZERO);
        let a = Uuid::now_v7();
        assert!(throttle.try_acquire(a));
        assert!(throttle.try_acquire(a));
    }
}
