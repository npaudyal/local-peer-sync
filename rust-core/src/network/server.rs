//! TCP server for handling peer connections

use crate::network::protocol::SyncMessage;
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
}

impl PeerServer {
    /// Create a new peer server
    pub fn new(config: SyncConfig) -> Self {
        Self {
            config,
            running: Arc::new(RwLock::new(false)),
            server_handle: None,
        }
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

        // Spawn the server in the background
        let running_clone = Arc::clone(&self.running);
        let handle = tokio::spawn(async move {
            if let Err(e) = Self::accept_connections(listener, running_clone).await {
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

    /// Accept incoming connections (now static method)
    async fn accept_connections(listener: TcpListener, running: Arc<RwLock<bool>>) -> Result<()> {
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

                    // Handle connection in a separate task
                    tokio::spawn(async move {
                        if let Err(e) = Self::handle_peer_connection(stream, addr).await {
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
    async fn handle_peer_connection(mut stream: TcpStream, addr: SocketAddr) -> Result<()> {
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
            Self::process_message(message, &mut stream).await?;
        }

        Ok(())
    }

    /// Process a received message
    async fn process_message(message: SyncMessage, stream: &mut TcpStream) -> Result<()> {
        // Handle different message types
        match message.message_type {
            crate::network::protocol::MessageType::Clipboard => {
                info!(
                    "Received clipboard sync: {}",
                    &message.payload[..message.payload.len().min(50)]
                );
                // TODO: Update local clipboard
            }
            crate::network::protocol::MessageType::Discovery => {
                info!(
                    "Received discovery message from device: {}",
                    message.source_device_id
                );
            }
            crate::network::protocol::MessageType::PairingRequest => {
                info!(
                    "Received pairing request from: {}",
                    message.source_device_id
                );
                // TODO: Show pairing prompt to user
            }
            crate::network::protocol::MessageType::PairingResponse => {
                info!(
                    "Received pairing response from: {}",
                    message.source_device_id
                );
                // TODO: Complete pairing process
            }
            crate::network::protocol::MessageType::Heartbeat => {
                debug!("Received heartbeat from: {}", message.source_device_id);
            }
        }

        // Send ACK response
        stream.write_all(b"ACK\n").await?;
        stream.flush().await?;

        Ok(())
    }
}
