pub mod discovery;
pub mod peer;
pub mod protocol;
pub mod server;
use crate::clipboard::ClipboardSyncEngine;
use crate::{Result, SyncConfig};
pub use discovery::DiscoveryService;
pub use peer::{Peer, PeerManager};
pub use protocol::{MessageType, SyncMessage};
pub use server::PeerServer;
use std::sync::Arc;
use tracing::info;
/// Main network synchronization manager
pub struct SyncManager {
    config: SyncConfig,
    discovery: Arc<DiscoveryService>,
    peer_manager: Arc<PeerManager>,
    server: Arc<tokio::sync::RwLock<PeerServer>>,
}
impl SyncManager {
    pub async fn new(config: SyncConfig) -> Result<Self> {
        config.validate()?;
        let peer_manager = Arc::new(PeerManager::new());
        let discovery = Arc::new(DiscoveryService::new(
            config.clone(),
            Arc::clone(&peer_manager),
        )?);
        let server = Arc::new(tokio::sync::RwLock::new(PeerServer::new(config.clone())));

        Ok(Self {
            config,
            discovery,
            peer_manager,
            server,
        })
    }

    /// Set the clipboard engine for the server to handle received clipboard data
    pub async fn set_clipboard_engine(&self, engine: Arc<ClipboardSyncEngine>) {
        let mut server = self.server.write().await;
        server.set_clipboard_engine(engine);
        info!("📋 Connected clipboard engine to network server");
    }

    pub async fn start_discovery(&mut self) -> Result<()> {
        info!("Starting peer discovery on port {}", self.config.port);

        // Start TCP server
        let mut server = self.server.write().await;
        server.start().await?;
        drop(server);

        // Start mDNS discovery
        self.discovery.start().await
    }

    pub async fn stop_discovery(&mut self) -> Result<()> {
        info!("Stopping peer discovery");

        // Stop mDNS discovery
        self.discovery.stop().await?;

        // Stop TCP server
        let mut server = self.server.write().await;
        server.stop().await?;

        Ok(())
    }

    pub async fn broadcast_clipboard(&self, content: String) -> Result<()> {
        let message = SyncMessage::new_clipboard(self.config.device_id.clone(), content);

        self.peer_manager.broadcast_message(message).await
    }

    pub async fn get_peer_names(&self) -> Vec<String> {
        self.peer_manager.get_peer_names().await
    }

    pub async fn get_discovered_peers(&self) -> Vec<discovery::DiscoveredPeer> {
        self.discovery.get_discovered_peers().await
    }
}
