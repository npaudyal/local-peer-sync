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

    /// 🆕 ENHANCED: Start discovery with iOS-specific handling
    pub async fn start_discovery(&mut self) -> Result<()> {
        info!("🚀 Starting peer discovery on port {}", self.config.port);

        // ✅ ALWAYS start TCP server (works on all platforms including iOS)
        let mut server = self.server.write().await;
        server.start().await?;
        drop(server);
        info!(
            "✅ TCP server started successfully on port {}",
            self.config.port
        );

        // 🆕 CONDITIONALLY start Rust mDNS discovery (skip on iOS)
        #[cfg(not(target_os = "ios"))]
        {
            info!("🔍 Starting Rust mDNS discovery (non-iOS platform)");
            self.discovery.start().await?;
            info!("✅ Rust mDNS discovery started successfully");
        }

        #[cfg(target_os = "ios")]
        {
            info!("📱 Skipping Rust mDNS on iOS - using native iOS discovery");
            info!("   ℹ️  iOS will handle mDNS through NetService");
            info!("   ℹ️  TCP server is running and ready for connections");
        }

        info!("🎉 Network discovery startup completed");
        Ok(())
    }

    /// 🆕 ENHANCED: Stop discovery with iOS-specific handling
    pub async fn stop_discovery(&mut self) -> Result<()> {
        info!("🛑 Stopping peer discovery");

        // 🆕 CONDITIONALLY stop Rust mDNS discovery (skip on iOS)
        #[cfg(not(target_os = "ios"))]
        {
            info!("🔍 Stopping Rust mDNS discovery (non-iOS platform)");
            self.discovery.stop().await?;
            info!("✅ Rust mDNS discovery stopped");
        }

        #[cfg(target_os = "ios")]
        {
            info!("📱 Skipping Rust mDNS stop on iOS - handled by Swift");
        }

        // ✅ ALWAYS stop TCP server
        let mut server = self.server.write().await;
        server.stop().await?;
        info!("✅ TCP server stopped");

        info!("🎉 Network discovery shutdown completed");
        Ok(())
    }

    /// Broadcast clipboard content to all connected peers
    pub async fn broadcast_clipboard(&self, content: String) -> Result<()> {
        let message = SyncMessage::new_clipboard(self.config.device_id.clone(), content);
        self.peer_manager.broadcast_message(message).await
    }

    /// Get peer names for display
    pub async fn get_peer_names(&self) -> Vec<String> {
        self.peer_manager.get_peer_names().await
    }

    /// 🆕 Get discovered peers (useful for iOS debugging)
    pub async fn get_discovered_peers(&self) -> Vec<discovery::DiscoveredPeer> {
        #[cfg(not(target_os = "ios"))]
        {
            self.discovery.get_discovered_peers().await
        }

        #[cfg(target_os = "ios")]
        {
            // On iOS, discovery is handled by Swift, so return empty vec
            info!("📱 get_discovered_peers called on iOS - returning empty (handled by Swift)");
            Vec::new()
        }
    }

    /// 🆕 Get peer manager for direct access (useful for iOS)
    pub async fn get_peer_manager(&self) -> Arc<PeerManager> {
        Arc::clone(&self.peer_manager)
    }

    /// 🆕 Get configuration
    pub fn get_config(&self) -> &SyncConfig {
        &self.config
    }

    /// 🆕 Health check method
    pub async fn health_check(&self) -> HealthStatus {
        let peer_count = self.peer_manager.get_peer_names().await.len();
        let server_running = {
            // Simple check - could be enhanced
            true // Assume running if we get here
        };

        HealthStatus {
            tcp_server_running: server_running,
            peer_count,
            rust_mdns_enabled: cfg!(not(target_os = "ios")),
            platform: std::env::consts::OS.to_string(),
        }
    }
}

/// 🆕 Health status for debugging
#[derive(Debug)]
pub struct HealthStatus {
    pub tcp_server_running: bool,
    pub peer_count: usize,
    pub rust_mdns_enabled: bool,
    pub platform: String,
}
