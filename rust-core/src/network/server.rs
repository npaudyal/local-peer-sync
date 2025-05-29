//! TCP server for handling peer connections
use crate::clipboard::{ClipboardContent, ClipboardItem, ClipboardSyncEngine};
use crate::network::protocol::{MessageType, SyncMessage, SyncPayload};
use crate::{Result, SyncConfig, SyncError};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::RwLock;
use tokio::task::JoinHandle;
use tracing::{debug, error, info, warn};
/// TCP server for handling peer connections
pub struct PeerServer {
    config: SyncConfig,
    running: Arc<RwLock<bool>>,
    server_handle: Option<JoinHandle<()>>,
    clipboard_engine: Option<Arc<ClipboardSyncEngine>>,
}
impl PeerServer {
    /// Create a new peer server
    pub fn new(config: SyncConfig) -> Self {
        Self {
            config,
            running: Arc::new(RwLock::new(false)),
            server_handle: None,
            clipboard_engine: None,
        }
    }
    /// Set the clipboard engine for processing received clipboard data
    pub fn set_clipboard_engine(&mut self, engine: Arc<ClipboardSyncEngine>) {
        self.clipboard_engine = Some(engine);
    }

    /// Start the TCP server
    pub async fn start(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }

        let addr = SocketAddr::from(([0, 0, 0, 0], self.config.port));
        let listener = TcpListener::bind(addr).await.map_err(SyncError::Network)?;

        info!("TCP server listening on {}", addr);

        *running = true;

        // Clone clipboard engine for the server task
        let clipboard_engine = self.clipboard_engine.clone();

        // Spawn the server in the background
        let running_clone = Arc::clone(&self.running);
        let handle = tokio::spawn(async move {
            if let Err(e) =
                Self::accept_connections(listener, running_clone, clipboard_engine).await
            {
                error!("TCP server error: {}", e);
            }
        });

        self.server_handle = Some(handle);

        Ok(())
    }

    /// Stop the TCP server
    pub async fn stop(&mut self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(());
        }

        info!("Stopping TCP server");
        *running = false;

        // Wait for server task to finish
        if let Some(handle) = self.server_handle.take() {
            handle.abort();
        }

        Ok(())
    }

    /// Accept incoming connections
    async fn accept_connections(
        listener: TcpListener,
        running: Arc<RwLock<bool>>,
        clipboard_engine: Option<Arc<ClipboardSyncEngine>>,
    ) -> Result<()> {
        loop {
            let is_running = {
                let running = running.read().await;
                *running
            };

            if !is_running {
                break;
            }

            match listener.accept().await {
                Ok((stream, addr)) => {
                    info!("New peer connection from: {}", addr);

                    // Clone clipboard engine for this connection
                    let clipboard_engine_clone = clipboard_engine.clone();

                    // Handle connection in a separate task
                    tokio::spawn(async move {
                        if let Err(e) =
                            Self::handle_peer_connection(stream, addr, clipboard_engine_clone).await
                        {
                            warn!("Error handling peer connection {}: {}", addr, e);
                        }
                    });
                }
                Err(e) => {
                    error!("Failed to accept connection: {}", e);
                    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                }
            }
        }

        info!("TCP server accept loop ended");
        Ok(())
    }

    /// Handle a peer connection
    async fn handle_peer_connection(
        mut stream: TcpStream,
        addr: SocketAddr,
        clipboard_engine: Option<Arc<ClipboardSyncEngine>>,
    ) -> Result<()> {
        loop {
            // Read message length (4 bytes, big endian)
            let mut length_buffer = [0u8; 4];
            match stream.read_exact(&mut length_buffer).await {
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    debug!("Peer {} disconnected", addr);
                    break;
                }
                Err(e) => {
                    return Err(SyncError::Network(e));
                }
            }

            let message_length = u32::from_be_bytes(length_buffer) as usize;

            // Validate message length
            if message_length > 10 * 1024 * 1024 {
                // 10MB max
                warn!("Message too large from {}: {} bytes", addr, message_length);
                break;
            }

            // Read message content
            let mut message_buffer = vec![0u8; message_length];
            stream.read_exact(&mut message_buffer).await?;

            // Parse message
            let message_str = String::from_utf8(message_buffer)
                .map_err(|e| SyncError::Unknown(format!("Invalid UTF-8: {}", e)))?;

            let message = SyncMessage::from_json(&message_str)?;
            debug!("Received message from {}: {:?}", addr, message.message_type);

            // Process the message
            Self::process_message(message, &mut stream, &clipboard_engine).await?;
        }

        Ok(())
    }

    /// Process a received message
    async fn process_message(
        message: SyncMessage,
        stream: &mut TcpStream,
        clipboard_engine: &Option<Arc<ClipboardSyncEngine>>,
    ) -> Result<()> {
        // Handle different message types
        match message.message_type {
            MessageType::ClipboardSync => {
                let summary = match &message.payload {
                    SyncPayload::Text(text) => {
                        // Apply text to clipboard!
                        if let Some(engine) = clipboard_engine {
                            let clipboard_item = ClipboardItem::new(
                                ClipboardContent::Text {
                                    content: text.clone(),
                                    encoding: "UTF-8".to_string(),
                                },
                                message.source_device_id.clone(),
                            );

                            match engine.set_clipboard_content(clipboard_item).await {
                                Ok(()) => {
                                    info!(
                                        "📋 ✅ Applied clipboard text from {}: {}",
                                        message.source_device_id,
                                        Self::truncate_for_log(text, 50)
                                    );
                                }
                                Err(e) => {
                                    warn!("📋 ❌ Failed to set clipboard text: {}", e);
                                }
                            }
                        } else {
                            warn!("📋 ❌ No clipboard engine available to apply content");
                        }

                        let preview = if text.len() > 50 {
                            format!("{}...", &text[..50])
                        } else {
                            text.clone()
                        };
                        format!("Text: {}", preview)
                    }
                    SyncPayload::ClipboardItem(item) => {
                        // Apply advanced clipboard item!
                        if let Some(engine) = clipboard_engine {
                            match engine.set_clipboard_content(item.clone()).await {
                                Ok(()) => {
                                    info!(
                                        "📋 ✅ Applied clipboard item from {}: {}",
                                        message.source_device_id,
                                        item.summary()
                                    );
                                }
                                Err(e) => {
                                    warn!("📋 ❌ Failed to set clipboard item: {}", e);
                                }
                            }
                        } else {
                            warn!("📋 ❌ No clipboard engine available to apply content");
                        }
                        format!("ClipboardItem: {}", item.summary())
                    }
                    _ => "Unknown payload type".to_string(),
                };

                info!(
                    "📨 Received clipboard sync from {}: {}",
                    message.source_device_id, summary
                );
            }
            MessageType::Discovery => {
                info!(
                    "🔍 Received discovery message from device: {}",
                    message.source_device_id
                );
            }
            MessageType::PairingRequest => {
                info!(
                    "🤝 Received pairing request from: {}",
                    message.source_device_id
                );
                // TODO: Show pairing prompt to user
            }
            MessageType::PairingResponse => {
                info!(
                    "🤝 Received pairing response from: {}",
                    message.source_device_id
                );
                // TODO: Complete pairing process
            }
            MessageType::Heartbeat => {
                debug!("💓 Received heartbeat from: {}", message.source_device_id);
            }
            MessageType::HistoryRequest => {
                info!(
                    "📚 Received history request from: {}",
                    message.source_device_id
                );
                // TODO: Send clipboard history
            }
            MessageType::HistoryResponse => {
                info!(
                    "📚 Received history response from: {}",
                    message.source_device_id
                );
                // TODO: Process clipboard history
            }
            MessageType::Statistics => {
                info!("📊 Received statistics from: {}", message.source_device_id);
                // TODO: Process statistics
            }
        }

        // Send ACK response
        stream.write_all(b"ACK\n").await?;
        stream.flush().await?;

        Ok(())
    }

    /// Truncate text for logging
    fn truncate_for_log(text: &str, max_len: usize) -> String {
        if text.len() > max_len {
            format!("{}...", &text[..max_len])
        } else {
            text.to_string()
        }
    }
}
