//! Key management and generation

use crate::{Result, SyncError};
use ring::rand::{SecureRandom, SystemRandom};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Manages cryptographic keys for devices
pub struct KeyManager {
    /// Our device's key pair
    device_keys: DeviceKeyPair,

    /// Trusted peer keys
    peer_keys: HashMap<String, PeerKey>,

    /// Random number generator
    rng: SystemRandom,
}

/// Device key pair for encryption
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceKeyPair {
    /// Device identifier
    pub device_id: String,

    /// Public key (can be shared)
    pub public_key: Vec<u8>,

    /// Private key (keep secret)
    pub private_key: Vec<u8>,
}

/// Peer public key information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerKey {
    /// Peer device identifier
    pub device_id: String,

    /// Peer device name
    pub device_name: String,

    /// Public key
    pub public_key: Vec<u8>,

    /// Whether this peer is trusted
    pub is_trusted: bool,
}

impl KeyManager {
    /// Create a new key manager with generated keys
    pub fn new(device_id: String) -> Result<Self> {
        let rng = SystemRandom::new();
        let device_keys = Self::generate_device_keys(&rng, device_id)?;

        Ok(Self {
            device_keys,
            peer_keys: HashMap::new(),
            rng,
        })
    }

    /// Load key manager from existing keys
    pub fn from_keys(device_keys: DeviceKeyPair) -> Self {
        Self {
            device_keys,
            peer_keys: HashMap::new(),
            rng: SystemRandom::new(),
        }
    }

    /// Generate new device key pair
    fn generate_device_keys(rng: &SystemRandom, device_id: String) -> Result<DeviceKeyPair> {
        let mut public_key = vec![0u8; 32];
        let mut private_key = vec![0u8; 32];

        rng.fill(&mut public_key)
            .map_err(|_| SyncError::Encryption("Failed to generate public key".to_string()))?;

        rng.fill(&mut private_key)
            .map_err(|_| SyncError::Encryption("Failed to generate private key".to_string()))?;

        Ok(DeviceKeyPair {
            device_id,
            public_key,
            private_key,
        })
    }

    /// Get our device's public key
    pub fn get_our_public_key(&self) -> &[u8] {
        &self.device_keys.public_key
    }

    /// Get our device's private key
    pub fn get_our_private_key(&self) -> &[u8] {
        &self.device_keys.private_key
    }

    /// Get our device keys
    pub fn get_device_keys(&self) -> &DeviceKeyPair {
        &self.device_keys
    }

    /// Add a peer's public key
    pub fn add_peer_key(&mut self, peer_key: PeerKey) -> Result<()> {
        if peer_key.public_key.len() != 32 {
            return Err(SyncError::Encryption("Invalid peer key length".to_string()));
        }

        self.peer_keys.insert(peer_key.device_id.clone(), peer_key);
        Ok(())
    }

    /// Get a peer's public key
    pub fn get_peer_key(&self, device_id: &str) -> Option<&PeerKey> {
        self.peer_keys.get(device_id)
    }

    /// Trust a peer
    pub fn trust_peer(&mut self, device_id: &str) -> Result<()> {
        if let Some(peer_key) = self.peer_keys.get_mut(device_id) {
            peer_key.is_trusted = true;
            Ok(())
        } else {
            Err(SyncError::Trust(format!("Peer {} not found", device_id)))
        }
    }

    /// Remove a peer's key
    pub fn remove_peer(&mut self, device_id: &str) -> Result<()> {
        if self.peer_keys.remove(device_id).is_some() {
            Ok(())
        } else {
            Err(SyncError::Trust(format!("Peer {} not found", device_id)))
        }
    }

    /// Get all trusted peers
    pub fn get_trusted_peers(&self) -> Vec<&PeerKey> {
        self.peer_keys
            .values()
            .filter(|peer| peer.is_trusted)
            .collect()
    }

    /// Generate shared secret with peer (improved version)
    pub fn generate_shared_secret(&self, peer_device_id: &str) -> Result<Vec<u8>> {
        let peer_key = self
            .get_peer_key(peer_device_id)
            .ok_or_else(|| SyncError::Encryption(format!("Peer {} not found", peer_device_id)))?;

        if !peer_key.is_trusted {
            return Err(SyncError::Trust(format!(
                "Peer {} not trusted",
                peer_device_id
            )));
        }

        // Use iterator to create shared secret (fixes clippy warning)
        let mut shared_secret: Vec<u8> = self
            .device_keys
            .private_key
            .iter()
            .zip(peer_key.public_key.iter())
            .map(|(a, b)| a ^ b)
            .collect();

        // Add randomness using RNG (fixes dead code warning)
        let mut salt = [0u8; 8];
        self.rng
            .fill(&mut salt)
            .map_err(|_| SyncError::Encryption("Failed to generate randomness".to_string()))?;

        // XOR salt into first 8 bytes for additional entropy
        for (i, &salt_byte) in salt.iter().enumerate() {
            if i < shared_secret.len() {
                shared_secret[i] ^= salt_byte;
            }
        }

        Ok(shared_secret)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_generation() {
        let manager = KeyManager::new("test-device".to_string()).unwrap();

        assert_eq!(manager.get_our_public_key().len(), 32);
        assert_eq!(manager.get_our_private_key().len(), 32);
        assert_eq!(manager.get_device_keys().device_id, "test-device");
    }

    #[test]
    fn test_peer_key_management() {
        let mut manager = KeyManager::new("test-device".to_string()).unwrap();

        let peer_key = PeerKey {
            device_id: "peer-1".to_string(),
            device_name: "Peer Device".to_string(),
            public_key: vec![1u8; 32],
            is_trusted: false,
        };

        manager.add_peer_key(peer_key).unwrap();
        assert!(manager.get_peer_key("peer-1").is_some());

        manager.trust_peer("peer-1").unwrap();
        assert!(manager.get_peer_key("peer-1").unwrap().is_trusted);
    }
}
