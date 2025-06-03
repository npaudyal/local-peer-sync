//
//  DiscoveryService.swift
//  LocalPeerSync - Simple Discovery (No Complex Resolution)
//

import Foundation
import Network
import os.log

class IOSDiscoveryService: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.localpeersync.ios", category: "Discovery")
    private let deviceName: String
    private let port: Int
    
    // mDNS components
    private var netService: NetService?
    private var browser: NetServiceBrowser?
    private var isRunning = false
    
    // Simple peer callback - just name
    private let onPeerFound: (String) -> Void
    
    init(deviceName: String, port: Int, onPeerFound: @escaping (String) -> Void) {
        self.deviceName = deviceName
        self.port = port
        self.onPeerFound = onPeerFound
        super.init()
    }
    
    func start() {
        guard !isRunning else { return }
        
        logger.info("🚀 Starting SIMPLE iOS discovery for device: \(self.deviceName)")
        
        startAdvertising()
        startBrowsing()
        
        isRunning = true
        logger.info("✅ Simple iOS discovery started successfully")
    }
    
    func stop() {
        guard isRunning else { return }
        
        logger.info("🛑 Stopping iOS discovery...")
        
        // Stop advertising
        netService?.stop()
        netService = nil
        
        // Stop browsing
        browser?.stop()
        browser = nil
        
        isRunning = false
        logger.info("✅ iOS discovery stopped")
    }
    
    private func startAdvertising() {
        netService = NetService(
            domain: "local.",
            type: "_localpeersync._tcp.",
            name: deviceName,
            port: Int32(port)
        )
        
        guard let service = netService else {
            logger.error("❌ Failed to create NetService")
            return
        }
        
        service.delegate = self
        let txtData = createTXTRecord()
        service.setTXTRecord(txtData)
        service.publish()
        
        logger.info("📡 Advertising iOS device: \(self.deviceName) on port \(self.port)")
    }
    
    private func startBrowsing() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_localpeersync._tcp.", inDomain: "local.")
        logger.info("🔍 Browsing for other LocalPeerSync devices...")
    }
    
    private func createTXTRecord() -> Data {
        let txtDict: [String: Data] = [
            "device_id": deviceName.data(using: .utf8) ?? Data(),
            "version": "1.0.0".data(using: .utf8) ?? Data(),
            "platform": "iOS".data(using: .utf8) ?? Data(),
            "port": "\(port)".data(using: .utf8) ?? Data(),
            "encryption": "true".data(using: .utf8) ?? Data()
        ]
        return NetService.data(fromTXTRecord: txtDict)
    }
}

// MARK: - NetService Delegate
extension IOSDiscoveryService: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        logger.info("✅ iOS device published successfully: \(sender.name)")
        logger.info("   📍 Type: \(sender.type)")
        logger.info("   🔌 Port: \(sender.port)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        logger.error("❌ Failed to publish iOS device: \(errorDict)")
    }
    
    func netServiceDidStop(_ sender: NetService) {
        logger.info("🛑 NetService stopped: \(sender.name)")
    }
}

// MARK: - NetServiceBrowser Delegate
extension IOSDiscoveryService: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name != deviceName else {
            logger.info("🚫 Ignoring our own service: \(service.name)")
            return
        }
        
        logger.info("🎯 FOUND peer service: \(service.name)")
        logger.info("   📍 Type: \(service.type)")
        logger.info("   🌐 Domain: \(service.domain)")
        
        // ✅ SIMPLE: Just add the peer immediately - no resolution needed!
        logger.info("✅ Adding peer immediately (no resolution): \(service.name)")
        onPeerFound(service.name)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        logger.info("🚫 Peer device left: \(service.name)")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        logger.info("🔍 Browser stopped searching")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        logger.error("❌ Browser search failed: \(errorDict)")
    }
    
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        logger.info("🔍 Browser will start searching...")
    }
}
