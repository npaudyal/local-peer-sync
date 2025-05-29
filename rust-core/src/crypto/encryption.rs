//! Encryption and decryption operations

use crate::{Result, SyncError};
use ring::aead::{
    Aad, BoundKey, Nonce, NonceSequence, OpeningKey, SealingKey, UnboundKey, AES_256_GCM, NONCE_LEN,
};
use ring::rand::{SecureRandom, SystemRandom};
use std::collections::HashMap;

/// Manages encryption/decryption for peer communications
pub struct EncryptionManager {
    /// Random number generator
    rng: SystemRandom,

    /// Encryption keys for trusted peers
    peer_keys: HashMap<String, Vec<u8>>,

    /// Our own encryption key
    our_key: Vec<u8>,
}

impl EncryptionManager {
    /// Create a new encryption manager
    pub fn new() -> Result<Self> {
        let rng = SystemRandom::new();
        let mut our_key = vec![0u8; 32]; // 256 bits
        rng.fill(&mut our_key)
            .map_err(|_| SyncError::Encryption("Failed to generate encryption key".to_string()))?;

        Ok(Self {
            rng,
            peer_keys: HashMap::new(),
            our_key,
        })
    }

    /// Add encryption key for a peer
    pub fn add_peer_key(&mut self, peer_id: String, key: Vec<u8>) -> Result<()> {
        if key.len() != 32 {
            return Err(SyncError::Encryption("Invalid key length".to_string()));
        }

        self.peer_keys.insert(peer_id, key);
        Ok(())
    }

    /// Encrypt data for a specific peer
    pub fn encrypt_for_peer(&self, peer_id: &str, data: &[u8]) -> Result<Vec<u8>> {
        let key = self
            .peer_keys
            .get(peer_id)
            .ok_or_else(|| SyncError::Encryption(format!("No key for peer: {}", peer_id)))?;

        self.encrypt_with_key(key, data)
    }

    /// Decrypt data from a specific peer
    pub fn decrypt_from_peer(&self, peer_id: &str, encrypted_data: &[u8]) -> Result<Vec<u8>> {
        let key = self
            .peer_keys
            .get(peer_id)
            .ok_or_else(|| SyncError::Encryption(format!("No key for peer: {}", peer_id)))?;

        self.decrypt_with_key(key, encrypted_data)
    }

    /// Encrypt data with our own key
    pub fn encrypt_with_our_key(&self, data: &[u8]) -> Result<Vec<u8>> {
        self.encrypt_with_key(&self.our_key, data)
    }

    /// Decrypt data with our own key
    pub fn decrypt_with_our_key(&self, encrypted_data: &[u8]) -> Result<Vec<u8>> {
        self.decrypt_with_key(&self.our_key, encrypted_data)
    }

    /// Get our public key for sharing
    pub fn get_our_key(&self) -> &[u8] {
        &self.our_key
    }

    /// Internal encryption with specific key
    fn encrypt_with_key(&self, key: &[u8], data: &[u8]) -> Result<Vec<u8>> {
        let unbound_key = UnboundKey::new(&AES_256_GCM, key)
            .map_err(|_| SyncError::Encryption("Invalid encryption key".to_string()))?;

        // Generate nonce
        let nonce_bytes = self.generate_nonce()?;
        let nonce = Nonce::try_assume_unique_for_key(&nonce_bytes)
            .map_err(|_| SyncError::Encryption("Invalid nonce".to_string()))?;

        let mut sealing_key = SealingKey::new(unbound_key, FixedNonceSequence::new(nonce));

        let mut encrypted_data = data.to_vec();

        sealing_key
            .seal_in_place_append_tag(Aad::empty(), &mut encrypted_data)
            .map_err(|_| SyncError::Encryption("Encryption failed".to_string()))?;

        // Prepend nonce to encrypted data
        let mut result = nonce_bytes.to_vec();
        result.extend_from_slice(&encrypted_data);

        Ok(result)
    }

    /// Internal decryption with specific key
    fn decrypt_with_key(&self, key: &[u8], encrypted_data: &[u8]) -> Result<Vec<u8>> {
        if encrypted_data.len() < NONCE_LEN {
            return Err(SyncError::Encryption(
                "Invalid encrypted data length".to_string(),
            ));
        }

        let (nonce_bytes, ciphertext) = encrypted_data.split_at(NONCE_LEN);
        let nonce = Nonce::try_assume_unique_for_key(nonce_bytes)
            .map_err(|_| SyncError::Encryption("Invalid nonce".to_string()))?;

        let unbound_key = UnboundKey::new(&AES_256_GCM, key)
            .map_err(|_| SyncError::Encryption("Invalid decryption key".to_string()))?;

        let mut opening_key = OpeningKey::new(unbound_key, FixedNonceSequence::new(nonce));
        let mut decrypted_data = ciphertext.to_vec();

        let plaintext = opening_key
            .open_in_place(Aad::empty(), &mut decrypted_data)
            .map_err(|_| SyncError::Encryption("Decryption failed".to_string()))?;

        Ok(plaintext.to_vec())
    }

    /// Generate a random nonce
    fn generate_nonce(&self) -> Result<[u8; NONCE_LEN]> {
        let mut nonce = [0u8; NONCE_LEN];
        self.rng
            .fill(&mut nonce)
            .map_err(|_| SyncError::Encryption("Failed to generate nonce".to_string()))?;
        Ok(nonce)
    }
}

/// Fixed nonce sequence that returns a pre-determined nonce once
struct FixedNonceSequence {
    nonce: Option<Nonce>,
}

impl FixedNonceSequence {
    fn new(nonce: Nonce) -> Self {
        Self { nonce: Some(nonce) }
    }
}

impl NonceSequence for FixedNonceSequence {
    fn advance(&mut self) -> core::result::Result<Nonce, ring::error::Unspecified> {
        self.nonce.take().ok_or(ring::error::Unspecified)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encryption_roundtrip() {
        let manager = EncryptionManager::new().unwrap();
        let data = b"Hello, World!";

        let encrypted = manager.encrypt_with_our_key(data).unwrap();
        let decrypted = manager.decrypt_with_our_key(&encrypted).unwrap();

        assert_eq!(data, decrypted.as_slice());
    }

    #[test]
    fn test_peer_encryption() {
        let mut manager = EncryptionManager::new().unwrap();
        let peer_key = vec![1u8; 32]; // Test key

        manager
            .add_peer_key("test-peer".to_string(), peer_key)
            .unwrap();

        let data = b"Secret message";
        let encrypted = manager.encrypt_for_peer("test-peer", data).unwrap();
        let decrypted = manager.decrypt_from_peer("test-peer", &encrypted).unwrap();

        assert_eq!(data, decrypted.as_slice());
    }

    #[test]
    fn test_invalid_key_length() {
        let mut manager = EncryptionManager::new().unwrap();
        let invalid_key = vec![1u8; 16]; // Wrong length

        let result = manager.add_peer_key("test-peer".to_string(), invalid_key);
        assert!(result.is_err());
    }

    #[test]
    fn test_missing_peer_key() {
        let manager = EncryptionManager::new().unwrap();
        let data = b"test data";

        let result = manager.encrypt_for_peer("nonexistent-peer", data);
        assert!(result.is_err());
    }

    #[test]
    fn test_invalid_encrypted_data() {
        let manager = EncryptionManager::new().unwrap();
        let invalid_data = b"too short"; // Less than nonce length

        let result = manager.decrypt_with_our_key(invalid_data);
        assert!(result.is_err());
    }
}
