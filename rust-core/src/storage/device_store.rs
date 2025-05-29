//! Persistent storage for device information

use crate::crypto::keys::{DeviceKeyPair, PeerKey};
use crate::{Result, SyncError};
use serde::{Deserialize, Serialize};
use sled::Db;
use std::path::Path;

/// Persistent storage for device and peer information
pub struct DeviceStore {
    /// Embedded database
    db: Db,
}

/// Stored device configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredDeviceInfo {
    pub device_id: String,
    pub device_name: String,
    pub keys: DeviceKeyPair,
    pub created_at: u64,
    pub last_updated: u64,
}

/// Stored peer information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredPeerInfo {
    pub peer_key: PeerKey,
    pub added_at: u64,
    pub last_seen: u64,
}

impl DeviceStore {
    /// Create or open device store at path
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let db = sled::open(path)
            .map_err(|e| SyncError::Storage(format!("Failed to open database: {}", e)))?;

        Ok(Self { db })
    }

    /// Store device information
    pub fn store_device_info(&self, info: &StoredDeviceInfo) -> Result<()> {
        let key = format!("device:{}", info.device_id);
        let value = bincode::serialize(info)
            .map_err(|e| SyncError::Storage(format!("Failed to serialize device info: {}", e)))?;

        self.db
            .insert(key.as_bytes(), value)
            .map_err(|e| SyncError::Storage(format!("Failed to store device info: {}", e)))?;

        self.db
            .flush()
            .map_err(|e| SyncError::Storage(format!("Failed to flush database: {}", e)))?;

        Ok(())
    }

    /// Load device information
    pub fn load_device_info(&self, device_id: &str) -> Result<Option<StoredDeviceInfo>> {
        let key = format!("device:{}", device_id);

        match self
            .db
            .get(key.as_bytes())
            .map_err(|e| SyncError::Storage(format!("Failed to load device info: {}", e)))?
        {
            Some(value) => {
                let info = bincode::deserialize(&value).map_err(|e| {
                    SyncError::Storage(format!("Failed to deserialize device info: {}", e))
                })?;
                Ok(Some(info))
            }
            None => Ok(None),
        }
    }

    /// Store peer information
    pub fn store_peer_info(&self, info: &StoredPeerInfo) -> Result<()> {
        let key = format!("peer:{}", info.peer_key.device_id);
        let value = bincode::serialize(info)
            .map_err(|e| SyncError::Storage(format!("Failed to serialize peer info: {}", e)))?;

        self.db
            .insert(key.as_bytes(), value)
            .map_err(|e| SyncError::Storage(format!("Failed to store peer info: {}", e)))?;

        Ok(())
    }

    /// Load peer information
    pub fn load_peer_info(&self, device_id: &str) -> Result<Option<StoredPeerInfo>> {
        let key = format!("peer:{}", device_id);

        match self
            .db
            .get(key.as_bytes())
            .map_err(|e| SyncError::Storage(format!("Failed to load peer info: {}", e)))?
        {
            Some(value) => {
                let info = bincode::deserialize(&value).map_err(|e| {
                    SyncError::Storage(format!("Failed to deserialize peer info: {}", e))
                })?;
                Ok(Some(info))
            }
            None => Ok(None),
        }
    }

    /// Load all stored peers
    pub fn load_all_peers(&self) -> Result<Vec<StoredPeerInfo>> {
        let mut peers = Vec::new();

        for result in self.db.scan_prefix(b"peer:") {
            let (_key, value) =
                result.map_err(|e| SyncError::Storage(format!("Failed to scan peers: {}", e)))?;

            let peer_info: StoredPeerInfo = bincode::deserialize(&value)
                .map_err(|e| SyncError::Storage(format!("Failed to deserialize peer: {}", e)))?;

            peers.push(peer_info);
        }

        Ok(peers)
    }

    /// Remove peer information
    pub fn remove_peer(&self, device_id: &str) -> Result<()> {
        let key = format!("peer:{}", device_id);

        self.db
            .remove(key.as_bytes())
            .map_err(|e| SyncError::Storage(format!("Failed to remove peer: {}", e)))?;

        Ok(())
    }

    /// Store configuration value
    pub fn store_config(&self, key: &str, value: &str) -> Result<()> {
        let config_key = format!("config:{}", key);

        self.db
            .insert(config_key.as_bytes(), value.as_bytes())
            .map_err(|e| SyncError::Storage(format!("Failed to store config: {}", e)))?;

        Ok(())
    }

    /// Load configuration value
    pub fn load_config(&self, key: &str) -> Result<Option<String>> {
        let config_key = format!("config:{}", key);

        match self
            .db
            .get(config_key.as_bytes())
            .map_err(|e| SyncError::Storage(format!("Failed to load config: {}", e)))?
        {
            Some(value) => {
                let config_value = String::from_utf8(value.to_vec())
                    .map_err(|e| SyncError::Storage(format!("Invalid config value: {}", e)))?;
                Ok(Some(config_value))
            }
            None => Ok(None),
        }
    }

    /// Clear all data (for testing)
    pub fn clear_all(&self) -> Result<()> {
        self.db
            .clear()
            .map_err(|e| SyncError::Storage(format!("Failed to clear database: {}", e)))?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};
    use tempfile::tempdir;

    #[test]
    fn test_device_storage() {
        let temp_dir = tempdir().unwrap();
        let store = DeviceStore::new(temp_dir.path().join("test.db")).unwrap();

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let device_info = StoredDeviceInfo {
            device_id: "test-device".to_string(),
            device_name: "Test Device".to_string(),
            keys: DeviceKeyPair {
                device_id: "test-device".to_string(),
                public_key: vec![1u8; 32],
                private_key: vec![2u8; 32],
            },
            created_at: now,
            last_updated: now,
        };

        store.store_device_info(&device_info).unwrap();
        let loaded = store.load_device_info("test-device").unwrap().unwrap();

        assert_eq!(loaded.device_id, device_info.device_id);
        assert_eq!(loaded.device_name, device_info.device_name);
    }

    #[test]
    fn test_peer_storage() {
        let temp_dir = tempdir().unwrap();
        let store = DeviceStore::new(temp_dir.path().join("test.db")).unwrap();

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let peer_info = StoredPeerInfo {
            peer_key: PeerKey {
                device_id: "peer-1".to_string(),
                device_name: "Peer Device".to_string(),
                public_key: vec![3u8; 32],
                is_trusted: true,
            },
            added_at: now,
            last_seen: now,
        };

        store.store_peer_info(&peer_info).unwrap();
        let loaded = store.load_peer_info("peer-1").unwrap().unwrap();

        assert_eq!(loaded.peer_key.device_id, peer_info.peer_key.device_id);
        assert_eq!(loaded.peer_key.device_name, peer_info.peer_key.device_name);
        assert_eq!(loaded.peer_key.is_trusted, true);
    }

    #[test]
    fn test_config_storage() {
        let temp_dir = tempdir().unwrap();
        let store = DeviceStore::new(temp_dir.path().join("test.db")).unwrap();

        store.store_config("auto_sync", "true").unwrap();
        let loaded = store.load_config("auto_sync").unwrap().unwrap();

        assert_eq!(loaded, "true");

        // Test non-existent config
        let missing = store.load_config("missing_key").unwrap();
        assert!(missing.is_none());
    }

    #[test]
    fn test_peer_removal() {
        let temp_dir = tempdir().unwrap();
        let store = DeviceStore::new(temp_dir.path().join("test.db")).unwrap();

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let peer_info = StoredPeerInfo {
            peer_key: PeerKey {
                device_id: "peer-to-remove".to_string(),
                device_name: "Removable Peer".to_string(),
                public_key: vec![4u8; 32],
                is_trusted: false,
            },
            added_at: now,
            last_seen: now,
        };

        // Store peer
        store.store_peer_info(&peer_info).unwrap();
        assert!(store.load_peer_info("peer-to-remove").unwrap().is_some());

        // Remove peer
        store.remove_peer("peer-to-remove").unwrap();
        assert!(store.load_peer_info("peer-to-remove").unwrap().is_none());
    }
}
