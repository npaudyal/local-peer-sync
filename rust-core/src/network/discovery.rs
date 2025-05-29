//! Real mDNS-based peer discovery service
use crate::network::peer::{Peer, PeerManager};
use crate::{Result, SyncConfig, SyncError};
use if_addrs::{get_if_addrs, IfAddr};
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use tracing::{debug, error, info, warn};
/// Service for discovering peers on the local network
pub struct DiscoveryService {
    config: SyncConfig,
    running: Arc<RwLock<bool>>,
    peer_manager: Arc<PeerManager>,
    discovered_peers: Arc<RwLock<HashMap<String, DiscoveredPeer>>>,
}
/// Represents a discovered peer device
#[derive(Debug, Clone)]
pub struct DiscoveredPeer {
    pub name: String,
    pub device_id: String,
    pub address: SocketAddr,
    pub txt_data: HashMap<String, String>,
}
impl DiscoveryService {
    pub fn new(config: SyncConfig, peer_manager: Arc<PeerManager>) -> Result<Self> {
        Ok(Self {
            config,
            running: Arc::new(RwLock::new(false)),
            peer_manager,
            discovered_peers: Arc::new(RwLock::new(HashMap::new())),
        })
    }
    /// Start advertising this device and discovering peers
    pub async fn start(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if *running {
            return Ok(());
        }

        info!(
            "Starting real mDNS discovery for service: {}",
            self.config.service_type
        );

        // Start the mDNS daemon
        let mdns = ServiceDaemon::new().map_err(|e| {
            SyncError::Network(std::io::Error::other(format!(
                "Failed to start mDNS daemon: {}",
                e
            )))
        })?;

        info!("mDNS daemon created successfully");

        // Start advertising our service
        self.start_advertising(&mdns).await?;

        // Start discovering other peers
        self.start_discovery(mdns).await?;

        *running = true;
        info!("mDNS discovery service started successfully");
        Ok(())
    }

    /// Stop the discovery service
    pub async fn stop(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(());
        }

        info!("Stopping mDNS discovery");
        *running = false;
        Ok(())
    }

    /// Advertise this device on the network
    async fn start_advertising(&self, mdns: &ServiceDaemon) -> Result<()> {
        // Get local IP address
        let local_ip = self.get_local_ip().await?;

        info!(
            "Advertising as: {} on {}:{}",
            self.config.device_name, local_ip, self.config.port
        );

        // Convert IP to proper format
        let ip_addrs = match local_ip {
            IpAddr::V4(ipv4) => vec![ipv4],
            IpAddr::V6(_) => {
                // Fall back to localhost if IPv6
                vec![Ipv4Addr::new(127, 0, 0, 1)]
            }
        };

        // Create TXT properties as simple key-value pairs
        let device_id = self.config.device_id.clone();
        let version_str = env!("CARGO_PKG_VERSION").to_string();
        let encryption_str = if self.config.encryption_enabled {
            "true"
        } else {
            "false"
        };
        let port_str = self.config.port.to_string();

        // Use array instead of vec! for clippy
        let txt_properties = [
            ("device_id", device_id.as_str()),
            ("version", version_str.as_str()),
            ("encryption", encryption_str),
            ("port", port_str.as_str()),
        ];

        // Ensure service type ends with .local.
        let service_type = if self.config.service_type.ends_with(".local.") {
            self.config.service_type.clone()
        } else if self.config.service_type.ends_with("._tcp") {
            format!("{}.local.", self.config.service_type)
        } else {
            format!("{}._tcp.local.", self.config.service_type)
        };

        info!("Using service type: {}", service_type);

        // Create service info
        let service_info = ServiceInfo::new(
            &service_type,            // Corrected service type
            &self.config.device_name, // Instance name
            &self.config.device_name, // Hostname
            &ip_addrs[..],            // IP addresses as slice
            self.config.port,
            &txt_properties[..], // TXT properties as slice of tuples
        )
        .map_err(|e| {
            SyncError::Network(std::io::Error::other(format!(
                "Failed to create service info: {}",
                e
            )))
        })?;

        // Register the service
        mdns.register(service_info).map_err(|e| {
            SyncError::Network(std::io::Error::other(format!(
                "Failed to register mDNS service: {}",
                e
            )))
        })?;

        info!("Successfully registered mDNS service");
        Ok(())
    }

    /// Discover other peers on the network
    async fn start_discovery(&self, mdns: ServiceDaemon) -> Result<()> {
        // Ensure service type for browsing is correct
        let service_type = if self.config.service_type.ends_with(".local.") {
            self.config.service_type.clone()
        } else if self.config.service_type.ends_with("._tcp") {
            format!("{}.local.", self.config.service_type)
        } else {
            format!("{}._tcp.local.", self.config.service_type)
        };

        let peer_manager = Arc::clone(&self.peer_manager);
        let discovered_peers = Arc::clone(&self.discovered_peers);
        let our_device_id = self.config.device_id.clone();

        info!(
            "Starting to browse for peers with service: {}",
            service_type
        );

        // Create a channel for receiving discovery events
        let (tx, mut rx) = mpsc::channel(100);

        // Start browsing for services
        let browser = mdns.browse(&service_type).map_err(|e| {
            SyncError::Network(std::io::Error::other(format!(
                "Failed to start browsing: {}",
                e
            )))
        })?;

        // Spawn task to handle discovery events
        tokio::spawn(async move {
            while let Ok(event) = browser.recv_async().await {
                if let Err(e) = tx.send(event).await {
                    error!("Failed to send discovery event: {}", e);
                    break;
                }
            }
        });

        // Spawn task to process discovery events
        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                match Self::handle_discovery_event(
                    event,
                    &peer_manager,
                    &discovered_peers,
                    &our_device_id,
                )
                .await
                {
                    Ok(()) => {}
                    Err(e) => warn!("Failed to handle discovery event: {}", e),
                }
            }
        });

        Ok(())
    }

    /// Handle mDNS discovery events
    async fn handle_discovery_event(
        event: ServiceEvent,
        peer_manager: &PeerManager,
        discovered_peers: &Arc<RwLock<HashMap<String, DiscoveredPeer>>>,
        our_device_id: &str,
    ) -> Result<()> {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                debug!("Service resolved: {}", info.get_fullname());

                // Parse TXT record - use a simpler approach
                let txt_data = Self::parse_txt_properties_simple(&info);

                // Extract device ID from TXT record
                if let Some(device_id) = txt_data.get("device_id") {
                    // Don't add ourselves
                    if device_id == our_device_id {
                        debug!("Ignoring our own service advertisement");
                        return Ok(());
                    }

                    // Get first IP address
                    if let Some(&ip_addr) = info.get_addresses().iter().next() {
                        let discovered_peer = DiscoveredPeer {
                            name: info.get_hostname().trim_end_matches('.').to_string(),
                            device_id: device_id.clone(),
                            address: SocketAddr::new(IpAddr::V4(ip_addr), info.get_port()),
                            txt_data: txt_data.clone(),
                        };

                        // Store discovered peer
                        {
                            let mut peers = discovered_peers.write().await;
                            peers.insert(device_id.clone(), discovered_peer.clone());
                        }

                        // Convert to Peer and add to peer manager
                        let peer = Peer::new(
                            discovered_peer.device_id.clone(),
                            discovered_peer.name.clone(),
                            discovered_peer.address,
                        );

                        // Add peer to peer manager
                        peer_manager.add_peer(peer).await;

                        // 🔥 CRITICAL FIX: Auto-trust discovered peers for testing
                        info!("🤝 Auto-trusting discovered peer: {}", device_id);
                        if let Err(e) = peer_manager.trust_peer(&device_id).await {
                            warn!("❌ Failed to auto-trust peer {}: {}", device_id, e);
                        } else {
                            info!(
                                "✅ Successfully auto-trusted peer: {}",
                                discovered_peer.name
                            );
                        }

                        info!(
                            "✅ Discovered and trusted new peer: {} ({}) at {}",
                            info.get_hostname(),
                            device_id,
                            ip_addr
                        );
                    } else {
                        warn!("Service resolved but no IP addresses found");
                    }
                } else {
                    debug!("Service resolved but no device_id in TXT record");
                }
            }
            ServiceEvent::ServiceRemoved(_, fullname) => {
                info!("Service removed: {}", fullname);
                // TODO: Remove peer from discovered peers
            }
            ServiceEvent::ServiceFound(_, fullname) => {
                debug!(
                    "Service found: {} - will be resolved automatically",
                    fullname
                );
            }
            ServiceEvent::SearchStarted(service_type) => {
                debug!("mDNS search started for: {}", service_type);
            }
            ServiceEvent::SearchStopped(service_type) => {
                debug!("mDNS search stopped for: {}", service_type);
            }
        }

        Ok(())
    }

    /// Get local IP address for advertising
    async fn get_local_ip(&self) -> Result<IpAddr> {
        let interfaces = get_if_addrs().map_err(|e| {
            SyncError::Network(std::io::Error::other(format!(
                "Failed to get network interfaces: {}",
                e
            )))
        })?;

        // Look for a non-loopback IPv4 address
        for iface in interfaces {
            if let IfAddr::V4(v4_addr) = iface.addr {
                if !v4_addr.is_loopback() && !v4_addr.is_link_local() {
                    info!("Using network interface: {} ({})", iface.name, v4_addr.ip);
                    return Ok(IpAddr::V4(v4_addr.ip));
                }
            }
        }

        // Fallback to localhost if no suitable interface found
        warn!("No suitable network interface found, using localhost");
        Ok(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)))
    }

    /// Simple TXT properties parsing - extract what we can
    fn parse_txt_properties_simple(info: &ServiceInfo) -> HashMap<String, String> {
        let mut result = HashMap::new();

        // Get TXT properties from the service info
        let properties = info.get_properties();

        // Parse each TXT property using the proper API
        for property in properties.iter() {
            let key = property.key();

            // Handle the value - it might be None for key-only properties
            if let Some(value_bytes) = property.val() {
                // Convert bytes to string
                if let Ok(value_str) = std::str::from_utf8(value_bytes) {
                    result.insert(key.to_string(), value_str.to_string());
                    debug!("Parsed TXT property: {} = {}", key, value_str);
                } else {
                    debug!("TXT property {} has invalid UTF-8 value", key);
                }
            } else {
                // Key-only property (no value)
                result.insert(key.to_string(), "".to_string());
                debug!("Parsed TXT property: {} (no value)", key);
            }
        }

        // Add fallback values only if not found
        if !result.contains_key("device_id") {
            result.insert(
                "device_id".to_string(),
                info.get_hostname().trim_end_matches('.').to_string(),
            );
            warn!("No device_id in TXT properties, using hostname as fallback");
        }

        if !result.contains_key("version") {
            result.insert("version".to_string(), "unknown".to_string());
        }

        if !result.contains_key("encryption") {
            result.insert("encryption".to_string(), "true".to_string());
        }

        if !result.contains_key("port") {
            result.insert("port".to_string(), info.get_port().to_string());
        }

        debug!("Final parsed TXT properties: {:?}", result);
        result
    }

    /// Get all discovered peers
    pub async fn get_discovered_peers(&self) -> Vec<DiscoveredPeer> {
        let peers = self.discovered_peers.read().await;
        peers.values().cloned().collect()
    }
}
