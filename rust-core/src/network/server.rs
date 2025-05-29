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
        info!("🚀 TCP server accept loop started, waiting for connections...");

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
                    info!("🔗 NEW CONNECTION! Peer connected from: {}", addr);

                    // Clone clipboard engine for this connection
                    let clipboard_engine_clone = clipboard_engine.clone();

                    // Handle connection in a separate task
                    tokio::spawn(async move {
                        info!("🔄 Spawning handler task for connection from: {}", addr);
                        if let Err(e) =
                            Self::handle_peer_connection(stream, addr, clipboard_engine_clone).await
                        {
                            warn!("❌ Error handling peer connection {}: {}", addr, e);
                        } else {
                            info!("✅ Connection from {} handled successfully", addr);
                        }
                    });
                }
                Err(e) => {
                    error!("❌ Failed to accept connection: {}", e);
                    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                }
            }
        }

        info!("🛑 TCP server accept loop ended");
        Ok(())
    }

    /// Handle a peer connection
    async fn handle_peer_connection(
        mut stream: TcpStream,
        addr: SocketAddr,
        clipboard_engine: Option<Arc<ClipboardSyncEngine>>,
    ) -> Result<()> {
        info!("🔍 Starting to handle connection from: {}", addr);

        loop {
            info!("📥 Waiting for message from: {}", addr);

            // Read message length (4 bytes, big endian)
            let mut length_buffer = [0u8; 4];
            match stream.read_exact(&mut length_buffer).await {
                Ok(_) => {
                    let message_length = u32::from_be_bytes(length_buffer) as usize;
                    info!(
                        "📏 Received message length: {} bytes from {}",
                        message_length, addr
                    );
                }
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    info!("👋 Peer {} disconnected (EOF)", addr);
                    break;
                }
                Err(e) => {
                    error!("❌ Error reading message length from {}: {}", addr, e);
                    return Err(SyncError::Network(e));
                }
            }

            let message_length = u32::from_be_bytes(length_buffer) as usize;

            // Validate message length
            if message_length > 10 * 1024 * 1024 {
                warn!(
                    "⚠️ Message too large from {}: {} bytes",
                    addr, message_length
                );
                break;
            }

            // Read message content
            info!(
                "📖 Reading {} bytes of message content from {}",
                message_length, addr
            );
            let mut message_buffer = vec![0u8; message_length];
            match stream.read_exact(&mut message_buffer).await {
                Ok(_) => {
                    info!("✅ Successfully read message content from {}", addr);
                }
                Err(e) => {
                    error!("❌ Error reading message content from {}: {}", addr, e);
                    return Err(SyncError::Network(e));
                }
            }

            // Parse message
            let message_str = String::from_utf8(message_buffer).map_err(|e| {
                error!("❌ Invalid UTF-8 from {}: {}", addr, e);
                SyncError::Unknown(format!("Invalid UTF-8: {}", e))
            })?;

            info!(
                "🔍 Parsing JSON message from {}: {} chars",
                addr,
                message_str.len()
            );

            let message = match SyncMessage::from_json(&message_str) {
                Ok(msg) => {
                    info!(
                        "✅ Successfully parsed message from {}: {:?}",
                        addr, msg.message_type
                    );
                    msg
                }
                Err(e) => {
                    error!("❌ Failed to parse message from {}: {}", addr, e);
                    error!("❌ Raw message: {}", message_str);
                    return Err(e);
                }
            };

            // Process the message
            info!("🔄 Processing message from {}", addr);
            match Self::process_message(message, &mut stream, &clipboard_engine).await {
                Ok(()) => {
                    info!("✅ Message processed successfully from {}", addr);
                }
                Err(e) => {
                    error!("❌ Error processing message from {}: {}", addr, e);
                    return Err(e);
                }
            }
        }

        info!("🔚 Connection handler for {} finished", addr);
        Ok(())
    }

    /// Process a received message
    async fn process_message(
        message: SyncMessage,
        stream: &mut TcpStream,
        clipboard_engine: &Option<Arc<ClipboardSyncEngine>>,
    ) -> Result<()> {
        info!(
            "🔍 Processing message type: {:?} from {}",
            message.message_type, message.source_device_id
        );

        // Handle different message types
        match message.message_type {
            MessageType::ClipboardSync => {
                info!(
                    "📨 Received clipboard sync message from: {}",
                    message.source_device_id
                );

                // Check if we have clipboard engine
                if clipboard_engine.is_none() {
                    error!("❌ No clipboard engine available! Cannot apply clipboard content.");
                    return Ok(());
                }

                let engine = clipboard_engine.as_ref().unwrap();
                info!("✅ Clipboard engine available, processing payload...");

                let summary = match &message.payload {
                    SyncPayload::Text(text) => {
                        info!("📝 Processing text payload: {} chars", text.len());

                        // Apply text to clipboard!
                        let clipboard_item = ClipboardItem::new(
                            ClipboardContent::Text {
                                content: text.clone(),
                                encoding: "UTF-8".to_string(),
                            },
                            message.source_device_id.clone(),
                        );

                        info!("🔄 Attempting to set clipboard content...");
                        match engine.set_clipboard_content(clipboard_item).await {
                            Ok(()) => {
                                info!(
                                    "📋 ✅ Successfully applied clipboard text from {}: {}",
                                    message.source_device_id,
                                    Self::truncate_for_log(text, 50)
                                );
                            }
                            Err(e) => {
                                error!("📋 ❌ Failed to set clipboard text: {}", e);
                            }
                        }

                        let preview = if text.len() > 50 {
                            format!("{}...", &text[..50])
                        } else {
                            text.clone()
                        };
                        format!("Text: {}", preview)
                    }
                    SyncPayload::ClipboardItem(item) => {
                        info!("📎 Processing clipboard item: {}", item.summary());

                        // Apply advanced clipboard item!
                        info!("🔄 Attempting to set clipboard item...");
                        match engine.set_clipboard_content(item.clone()).await {
                            Ok(()) => {
                                info!(
                                    "📋 ✅ Successfully applied clipboard item from {}: {}",
                                    message.source_device_id,
                                    item.summary()
                                );
                            }
                            Err(e) => {
                                error!("📋 ❌ Failed to set clipboard item: {}", e);
                            }
                        }
                        format!("ClipboardItem: {}", item.summary())
                    }
                    _ => {
                        warn!("❓ Unknown payload type in clipboard sync message");
                        "Unknown payload type".to_string()
                    }
                };

                info!(
                    "📨 ✅ Processed clipboard sync from {}: {}",
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
            }
            MessageType::PairingResponse => {
                info!(
                    "🤝 Received pairing response from: {}",
                    message.source_device_id
                );
            }
            MessageType::Heartbeat => {
                debug!("💓 Received heartbeat from: {}", message.source_device_id);
            }
            MessageType::HistoryRequest => {
                info!(
                    "📚 Received history request from: {}",
                    message.source_device_id
                );
            }
            MessageType::HistoryResponse => {
                info!(
                    "📚 Received history response from: {}",
                    message.source_device_id
                );
            }
            MessageType::Statistics => {
                info!("📊 Received statistics from: {}", message.source_device_id);
            }
        }

        // Send ACK response
        info!("📤 Sending ACK response...");
        stream.write_all(b"ACK\n").await?;
        stream.flush().await?;
        info!("✅ ACK sent successfully");

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
