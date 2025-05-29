//! Peer management and communication

use crate::network::protocol::SyncMessage;
use crate::{Result, SyncError};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Represents a discovered peer device
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Peer {
    /// Unique device identifier
    pub device_id: String,

    /// Human-readable device name
    pub device_name: String,

    /// Network address
    pub address: SocketAddr,

    /// Whether this peer is trusted (paired)
    pub is_trusted: bool,

    /// Last seen timestamp (as Unix timestamp for serialization)
    #[serde(with = "timestamp_serde")]
    pub last_seen: Instant,

    /// Connection status
    pub is_connected: bool,
}

/// Custom serialization for Instant as Unix timestamp
mod timestamp_serde {
    use serde::{Deserialize, Deserializer, Serialize, Serializer};
    use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH}; // Keep them here where they're used

    pub fn serialize<S>(instant: &Instant, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        // Convert Instant to approximate Unix timestamp
        // Note: This is approximate since Instant doesn't have a fixed epoch
        let system_time = SystemTime::now();
        let elapsed_since_instant = instant.elapsed();
        let approx_timestamp = system_time
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .saturating_sub(elapsed_since_instant)
            .as_secs();

        approx_timestamp.serialize(serializer)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Instant, D::Error>
    where
        D: Deserializer<'de>,
    {
        let timestamp = u64::deserialize(deserializer)?;

        // Convert back to Instant (approximate)
        let system_time = SystemTime::now();
        let current_timestamp = system_time
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();

        let duration_ago = current_timestamp.saturating_sub(timestamp);
        Ok(Instant::now() - Duration::from_secs(duration_ago))
    }
}

impl Peer {
    pub fn new(device_id: String, device_name: String, address: SocketAddr) -> Self {
        Self {
            device_id,
            device_name,
            address,
            is_trusted: false,
            last_seen: Instant::now(),
            is_connected: false,
        }
    }

    /// Check if peer is online (seen within last 60 seconds)
    pub fn is_online(&self) -> bool {
        self.last_seen.elapsed() < Duration::from_secs(60)
    }

    /// Update last seen timestamp
    pub fn update_last_seen(&mut self) {
        self.last_seen = Instant::now();
    }

    /// Mark peer as trusted
    pub fn set_trusted(&mut self, trusted: bool) {
        self.is_trusted = trusted;
    }
}

/// Manages all discovered and trusted peers
pub struct PeerManager {
    /// All discovered peers
    peers: Arc<RwLock<HashMap<String, Peer>>>,

    /// Active connections to peers
    connections: Arc<RwLock<HashMap<String, TcpStream>>>,
}

impl PeerManager {
    pub fn new() -> Self {
        Self {
            peers: Arc::new(RwLock::new(HashMap::new())),
            connections: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Add or update a discovered peer
    pub async fn add_peer(&self, peer: Peer) {
        let mut peers = self.peers.write().await;

        if let Some(existing_peer) = peers.get_mut(&peer.device_id) {
            // Update existing peer
            existing_peer.address = peer.address;
            existing_peer.device_name = peer.device_name;
            existing_peer.update_last_seen();
            debug!("Updated peer: {}", existing_peer.device_name);
        } else {
            // Add new peer
            info!(
                "Discovered new peer: {} ({})",
                peer.device_name, peer.device_id
            );
            peers.insert(peer.device_id.clone(), peer);
        }
    }

    /// Get all trusted peers
    pub async fn get_trusted_peers(&self) -> Vec<Peer> {
        let peers = self.peers.read().await;
        peers
            .values()
            .filter(|peer| peer.is_trusted && peer.is_online())
            .cloned()
            .collect()
    }

    /// Get all discovered peers
    pub async fn get_all_peers(&self) -> Vec<Peer> {
        let peers = self.peers.read().await;
        peers.values().cloned().collect()
    }

    /// Trust a peer (complete pairing)
    pub async fn trust_peer(&self, device_id: &str) -> Result<()> {
        let mut peers = self.peers.write().await;

        if let Some(peer) = peers.get_mut(device_id) {
            peer.set_trusted(true);
            info!("Peer {} is now trusted", peer.device_name);
            Ok(())
        } else {
            Err(SyncError::Trust(format!("Peer {} not found", device_id)))
        }
    }

    /// Remove a peer
    pub async fn remove_peer(&self, device_id: &str) -> Result<()> {
        let mut peers = self.peers.write().await;
        let mut connections = self.connections.write().await;

        // Close connection if exists
        if let Some(_connection) = connections.remove(device_id) {
            debug!("Closed connection to peer {}", device_id);
        }

        // Remove peer
        if let Some(peer) = peers.remove(device_id) {
            info!("Removed peer: {}", peer.device_name);
            Ok(())
        } else {
            Err(SyncError::Trust(format!("Peer {} not found", device_id)))
        }
    }

    /// Broadcast a message to all trusted peers
    /// Broadcast a message to all trusted peers
    pub async fn broadcast_message(&self, message: SyncMessage) -> Result<()> {
        let trusted_peers = self.get_trusted_peers().await;

        if trusted_peers.is_empty() {
            debug!("No trusted peers to broadcast to");
            return Ok(());
        }

        let message_json = message.to_json()?;
        let mut success_count = 0;

        // Use &trusted_peers to iterate by reference instead of moving
        for peer in &trusted_peers {
            // <- Add & here
            match self.send_message_to_peer(peer, &message_json).await {
                // peer is already &Peer
                Ok(()) => {
                    success_count += 1;
                    debug!("Message sent to peer: {}", peer.device_name);
                }
                Err(e) => {
                    warn!("Failed to send message to {}: {}", peer.device_name, e);
                }
            }
        }

        info!(
            "Broadcast message to {}/{} peers",
            success_count,
            trusted_peers.len() // Now this works because trusted_peers wasn't moved
        );
        Ok(())
    }

    /// Send a message to a specific peer
    async fn send_message_to_peer(&self, peer: &Peer, message: &str) -> Result<()> {
        // Try to establish connection if not exists
        let mut stream = TcpStream::connect(peer.address).await?;

        // Send message length first (4 bytes, big endian)
        let message_bytes = message.as_bytes();
        let length = message_bytes.len() as u32;
        stream.write_all(&length.to_be_bytes()).await?;

        // Send message content
        stream.write_all(message_bytes).await?;
        stream.flush().await?;

        // Read response (simple ACK)
        let mut response = [0u8; 4];
        stream.read_exact(&mut response).await?;

        if &response == b"ACK\n" {
            Ok(())
        } else {
            Err(SyncError::Network(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Invalid response from peer",
            )))
        }
    }

    /// Clean up offline peers
    pub async fn cleanup_offline_peers(&self) {
        let mut peers = self.peers.write().await;
        let mut to_remove = Vec::new();

        for (device_id, peer) in peers.iter() {
            if !peer.is_online() {
                to_remove.push(device_id.clone());
            }
        }

        for device_id in to_remove {
            if let Some(peer) = peers.remove(&device_id) {
                info!("Removed offline peer: {}", peer.device_name);
            }
        }
    }

    /// Get peer names for display
    pub async fn get_peer_names(&self) -> Vec<String> {
        let peers = self.peers.read().await;
        peers
            .values()
            .filter(|peer| peer.is_online())
            .map(|peer| peer.device_name.clone())
            .collect()
    }
}

impl Default for PeerManager {
    fn default() -> Self {
        Self::new()
    }
}
