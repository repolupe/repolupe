use crate::config::error::AppError;
use argon2::Argon2;
use argon2::password_hash::{PasswordHasher, PasswordVerifier};

/// Argon2 takes tens of milliseconds of CPU, so it runs on the blocking thread pool
/// instead of stalling the async workers.
pub(crate) async fn hash_password(password: &str) -> Result<String, AppError> {
    let password = password.to_string();
    tokio::task::spawn_blocking(move || hash(&password))
        .await
        .map_err(|e| AppError::InternalServerError(format!("Password hashing panicked: {e}")))?
        .map_err(|e| AppError::InternalServerError(format!("Failed to hash password: {e}")))
}

/// See [`hash_password`].
pub(crate) async fn verify_password(password: &str, password_hash: &str) -> Result<bool, AppError> {
    let password = password.to_string();
    let password_hash = password_hash.to_string();
    tokio::task::spawn_blocking(move || verify(&password, &password_hash))
        .await
        .map_err(|e| AppError::InternalServerError(format!("Password verification panicked: {e}")))
}

fn hash(password: &str) -> Result<String, argon2::password_hash::Error> {
    Ok(Argon2::default()
        .hash_password(password.as_bytes())?
        .to_string())
}

fn verify(password: &str, password_hash: &str) -> bool {
    Argon2::default()
        .verify_password(password.as_bytes(), password_hash)
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_and_verify_roundtrip() {
        let hash = hash("correct horse battery staple").unwrap();
        assert!(verify("correct horse battery staple", &hash));
        assert!(!verify("wrong password", &hash));
    }

    #[test]
    fn hashes_are_salted() {
        let a = hash("same").unwrap();
        let b = hash("same").unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn invalid_hash_does_not_verify() {
        assert!(!verify("anything", "not-a-hash"));
    }

    #[tokio::test]
    async fn async_roundtrip() {
        let hash = hash_password("correct horse battery staple").await.unwrap();
        assert!(
            verify_password("correct horse battery staple", &hash)
                .await
                .unwrap()
        );
        assert!(!verify_password("wrong password", &hash).await.unwrap());
    }
}
