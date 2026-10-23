use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use sha2::{Digest, Sha256};
use uuid::Uuid;

const NONCE_LENGTH: usize = 12;

/// Hashing does not add entropy, so short secrets are rejected.
const MIN_SECRET_LENGTH: usize = 32;

/// Encrypts repository access tokens and LLM API keys with AES-256-GCM.
///
/// Changing the key makes all stored tokens unreadable, so they have to be entered again.
pub(crate) struct TokenCipher {
    cipher: Aes256Gcm,
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum TokenCipherError {
    #[error("secret must be at least {MIN_SECRET_LENGTH} characters long")]
    SecretTooShort,

    #[error("token could not be encrypted or decrypted")]
    Crypto,
}

impl TokenCipher {
    /// Derives the 256-bit key as the SHA-256 hash of `secret`.
    pub(crate) fn from_secret(secret: &str) -> Result<Self, TokenCipherError> {
        let secret = secret.trim();
        if secret.chars().count() < MIN_SECRET_LENGTH {
            return Err(TokenCipherError::SecretTooShort);
        }
        let key = Sha256::digest(secret.as_bytes());
        Ok(Self {
            cipher: Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&key)),
        })
    }

    /// Returns `nonce || ciphertext || tag`. `owner_id`, the id of the row the token is stored
    /// in, is bound as associated data, so a ciphertext copied to another row fails to decrypt.
    pub(crate) fn encrypt(&self, owner_id: Uuid, token: &str) -> Result<Vec<u8>, TokenCipherError> {
        let nonce: [u8; NONCE_LENGTH] = rand::random();
        let payload = Payload {
            msg: token.as_bytes(),
            aad: owner_id.as_bytes(),
        };
        let sealed = self
            .cipher
            .encrypt(Nonce::from_slice(&nonce), payload)
            .map_err(|_| TokenCipherError::Crypto)?;

        let mut ciphertext = Vec::with_capacity(NONCE_LENGTH + sealed.len());
        ciphertext.extend_from_slice(&nonce);
        ciphertext.extend_from_slice(&sealed);
        Ok(ciphertext)
    }

    pub(crate) fn decrypt(
        &self,
        owner_id: Uuid,
        ciphertext: &[u8],
    ) -> Result<String, TokenCipherError> {
        if ciphertext.len() < NONCE_LENGTH {
            return Err(TokenCipherError::Crypto);
        }
        let (nonce, sealed) = ciphertext.split_at(NONCE_LENGTH);
        let payload = Payload {
            msg: sealed,
            aad: owner_id.as_bytes(),
        };
        let plain = self
            .cipher
            .decrypt(Nonce::from_slice(nonce), payload)
            .map_err(|_| TokenCipherError::Crypto)?;
        String::from_utf8(plain).map_err(|_| TokenCipherError::Crypto)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: &str = "a long secret that is used only for tests 1";
    const OTHER_KEY: &str = "a long secret that is used only for tests 2";

    #[test]
    fn roundtrip() {
        let cipher = TokenCipher::from_secret(KEY).unwrap();
        let id = Uuid::now_v7();
        let encrypted = cipher.encrypt(id, "ghp_secret").unwrap();
        assert_eq!(cipher.decrypt(id, &encrypted).unwrap(), "ghp_secret");
    }

    #[test]
    fn rejects_other_owner_id() {
        let cipher = TokenCipher::from_secret(KEY).unwrap();
        let encrypted = cipher.encrypt(Uuid::now_v7(), "token").unwrap();
        assert!(cipher.decrypt(Uuid::now_v7(), &encrypted).is_err());
    }

    #[test]
    fn rejects_other_key() {
        let id = Uuid::now_v7();
        let encrypted = TokenCipher::from_secret(KEY)
            .unwrap()
            .encrypt(id, "token")
            .unwrap();
        let other = TokenCipher::from_secret(OTHER_KEY).unwrap();
        assert!(other.decrypt(id, &encrypted).is_err());
    }

    #[test]
    fn rejects_short_secrets() {
        assert!(TokenCipher::from_secret("").is_err());
        assert!(TokenCipher::from_secret(&"x".repeat(31)).is_err());
        assert!(TokenCipher::from_secret(&format!("  {}  ", "x".repeat(31))).is_err());
        assert!(TokenCipher::from_secret(&"x".repeat(32)).is_ok());
    }
}
