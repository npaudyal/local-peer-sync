//! Real mDNS-based peer discovery service
use crate::network::peer::{Peer, PeerManager};
use crate::{Result, SyncConfig, SyncError};
use if_addrs::{get_if_addrs, IfAddr};
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use tracing::{error, info, warn};

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
            "🚀 Starting ENHANCED mDNS discovery for service: {}",
            self.config.service_type
        );

        // Start the mDNS daemon
        let mdns = ServiceDaemon::new().map_err(|e| {
            SyncError::Network(std::io::Error::other(format!(
                "Failed to start mDNS daemon: {}",
                e
            )))
        })?;

        info!("✅ mDNS daemon created successfully");

        // Start advertising our service
        self.start_advertising(&mdns).await?;

        // Start discovering other peers
        self.start_discovery(mdns).await?;

        *running = true;
        info!("🎉 ENHANCED mDNS discovery service started successfully");
        Ok(())
    }

    /// Stop the discovery service
    pub async fn stop(&self) -> Result<()> {
        let mut running = self.running.write().await;
        if !*running {
            return Ok(());
        }

        info!("🛑 Stopping mDNS discovery");
        *running = false;
        Ok(())
    }

    /// Advertise this device on the network
    async fn start_advertising(&self, mdns: &ServiceDaemon) -> Result<()> {
        // Get local IP address with enhanced logic
        let local_ip = self.get_local_ip().await?;

        info!("🎯 ADVERTISING DETAILS:");
        info!("   📱 Device: {}", self.config.device_name);
        info!("   🆔 ID: {}", self.config.device_id);
        info!("   🌐 IP: {}", local_ip);
        info!("   🔌 Port: {}", self.config.port);

        // Convert IP to proper format
        let ip_addrs = match local_ip {
            IpAddr::V4(ipv4) => vec![ipv4],
            IpAddr::V6(_) => {
                warn!("⚠️ IPv6 address, falling back to localhost");
                vec![Ipv4Addr::new(127, 0, 0, 1)]
            }
        };

        // Create TXT properties to match what Mac is sending
        let device_id = self.config.device_id.clone();
        let version_str = env!("CARGO_PKG_VERSION").to_string();
        let encryption_str = if self.config.encryption_enabled {
            "true"
        } else {
            "false"
        };
        let port_str = self.config.port.to_string();

        let txt_properties = [
            ("device_id", device_id.as_str()),
            ("version", version_str.as_str()),
            ("encryption", encryption_str),
            ("port", port_str.as_str()),
        ];

        info!("📝 TXT Properties: {:?}", txt_properties);

        // Ensure service type is EXACTLY like Mac
        let service_type = "_localpeersync._tcp.local.";
        info!("🔧 Using EXACT service type: {}", service_type);

        // Create service info
        let service_info = ServiceInfo::new(
            service_type,             // Use exact service type
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

        info!("🎉 Successfully registered mDNS service");
        info!(
            "🔍 Other devices should now see: {}",
            self.config.device_name
        );
        Ok(())
    }

    /// Discover other peers on the network
    async fn start_discovery(&self, mdns: ServiceDaemon) -> Result<()> {
        // Use EXACT service type to match Mac
        let service_type = "_localpeersync._tcp.local.";

        let peer_manager = Arc::clone(&self.peer_manager);
        let discovered_peers = Arc::clone(&self.discovered_peers);
        let our_device_id = self.config.device_id.clone();

        info!("🔍 Starting peer discovery for: {}", service_type);
        info!("🚫 Ignoring our own device: {}", &our_device_id[..8]);

        // Create a channel for receiving discovery events
        let (tx, mut rx) = mpsc::channel(100);

        // Start browsing for services
        let browser = mdns.browse(service_type).map_err(|e| {
            SyncError::Network(std::io::Error::other(format!(
                "Failed to start browsing: {}",
                e
            )))
        })?;

        info!("✅ mDNS browser created successfully");

        // Spawn task to handle discovery events
        tokio::spawn(async move {
            info!("🔄 Starting mDNS event receiver loop...");
            while let Ok(event) = browser.recv_async().await {
                info!("📡 Received mDNS event, forwarding to handler...");
                if let Err(e) = tx.send(event).await {
                    error!("❌ Failed to send discovery event: {}", e);
                    break;
                }
            }
            warn!("🛑 mDNS event receiver loop ended");
        });

        // Spawn task to process discovery events
        tokio::spawn(async move {
            info!("🔄 Starting mDNS event processor loop...");
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
                    Err(e) => warn!("⚠️ Failed to handle discovery event: {}", e),
                }
            }
            warn!("🛑 mDNS event processor loop ended");
        });

        info!("🎉 Discovery loops started successfully");
        Ok(())
    }

    /// Handle mDNS discovery events with ENHANCED debugging
    async fn handle_discovery_event(
        event: ServiceEvent,
        peer_manager: &PeerManager,
        discovered_peers: &Arc<RwLock<HashMap<String, DiscoveredPeer>>>,
        our_device_id: &str,
    ) -> Result<()> {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                let txt_data = Self::parse_txt_properties_enhanced(&info);

                if let Some(device_id) = txt_data.get("device_id") {
                    if device_id == our_device_id {
                        return Ok(()); // Ignore our own service
                    }

                    if let Some(&ip_addr) = info.get_addresses().iter().next() {
                        println!(
                            "🔗 Found device: {} at {}",
                            info.get_hostname().trim_end_matches('.'),
                            ip_addr
                        );

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

                        peer_manager.add_peer(peer).await;

                        // Auto-trust discovered peers
                        if let Err(_) = peer_manager.trust_peer(&device_id).await {
                            // Silent fail
                        } else {
                            println!("✅ Connected to: {}", discovered_peer.name);
                        }
                    }
                }
            }
            ServiceEvent::ServiceRemoved(_, fullname) => {
                if !fullname.contains(our_device_id) {
                    println!("👋 Device disconnected");
                }
            }
            ServiceEvent::SearchStarted(_) => {
                // Silent
            }
            ServiceEvent::SearchStopped(_) => {
                // Silent
            }
            _ => {
                // Ignore other events silently
            }
        }

        Ok(())
    }

    /// Enhanced TXT properties parsing with better debugging
    fn parse_txt_properties_enhanced(info: &ServiceInfo) -> HashMap<String, String> {
        let mut result = HashMap::new();
        let properties = info.get_properties();

        info!("🔍 Parsing TXT properties:");
        info!("   📝 Property count: {}", properties.iter().count());

        for property in properties.iter() {
            let key = property.key();
            info!("   🔑 Processing key: '{}'", key);

            if let Some(value_bytes) = property.val() {
                match std::str::from_utf8(value_bytes) {
                    Ok(value_str) => {
                        result.insert(key.to_string(), value_str.to_string());
                        info!("     ✅ {} = '{}'", key, value_str);
                    }
                    Err(e) => {
                        warn!("     ❌ Invalid UTF-8 for key '{}': {}", key, e);
                    }
                }
            } else {
                result.insert(key.to_string(), "".to_string());
                info!("     📝 {} = (empty)", key);
            }
        }

        // Enhanced fallback with debugging
        if !result.contains_key("device_id") {
            let fallback_id = info.get_hostname().trim_end_matches('.').to_string();
            result.insert("device_id".to_string(), fallback_id.clone());
            warn!(
                "⚠️ No device_id found, using hostname as fallback: {}",
                fallback_id
            );
        }

        info!("📋 Final TXT properties: {:?}", result);
        result
    }

    /// Enhanced local IP detection with WiFi preference
    async fn get_local_ip(&self) -> Result<IpAddr> {
        let interfaces = get_if_addrs().map_err(|e| {
            SyncError::Network(std::io::Error::other(format!(
                "Failed to get network interfaces: {}",
                e
            )))
        })?;

        info!("🔍 All available network interfaces:");
        for iface in &interfaces {
            info!("  - {}: {:?}", iface.name, iface.addr);
        }

        // Priority order for interface selection
        let preferred_interfaces = ["en0", "eth0", "wlan0", "Wi-Fi"]; // WiFi interfaces first
        let avoid_interfaces = ["pdp_ip", "cellular", "lo", "utun"]; // Avoid cellular and tunnels

        // First pass: Look for preferred WiFi interfaces
        for preferred in &preferred_interfaces {
            for iface in &interfaces {
                if iface.name.contains(preferred) {
                    if let IfAddr::V4(ref v4_addr) = iface.addr {
                        if !v4_addr.is_loopback() && !v4_addr.is_link_local() {
                            info!(
                                "✅ Selected preferred WiFi interface: {} ({})",
                                iface.name, v4_addr.ip
                            );
                            return Ok(IpAddr::V4(v4_addr.ip));
                        }
                    }
                }
            }
        }

        // Second pass: Any non-cellular, non-loopback IPv4 interface
        for iface in &interfaces {
            // Skip unwanted interfaces
            if avoid_interfaces
                .iter()
                .any(|avoid| iface.name.contains(avoid))
            {
                continue;
            }

            if let IfAddr::V4(ref v4_addr) = iface.addr {
                if !v4_addr.is_loopback() && !v4_addr.is_link_local() {
                    info!(
                        "✅ Selected fallback interface: {} ({})",
                        iface.name, v4_addr.ip
                    );
                    return Ok(IpAddr::V4(v4_addr.ip));
                }
            }
        }

        // Third pass: Try IPv6 if no IPv4 found
        for iface in &interfaces {
            if avoid_interfaces
                .iter()
                .any(|avoid| iface.name.contains(avoid))
            {
                continue;
            }

            if let IfAddr::V6(ref v6_addr) = iface.addr {
                if !v6_addr.is_loopback() {
                    warn!("⚠️ Using IPv6 interface: {} ({})", iface.name, v6_addr.ip);
                    return Ok(IpAddr::V6(v6_addr.ip));
                }
            }
        }

        // Fallback to localhost if no suitable interface found
        error!("❌ No suitable network interface found, using localhost");
        Ok(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)))
    }

    /// Get all discovered peers
    pub async fn get_discovered_peers(&self) -> Vec<DiscoveredPeer> {
        let peers = self.discovered_peers.read().await;
        peers.values().cloned().collect()
    }
}
