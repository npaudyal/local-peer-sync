//
//  QRCodeSharingView.swift
//  LocalPeerSync
//
//  QR code sharing for easy device pairing
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeSharingView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var syncService: SyncService
    @State private var qrCodeImage: UIImage?
    @State private var showingShareSheet = false
    @State private var isLoading = true
    
    private var connectionInfo: String {
        let info: [String: Any] = [
            "name": syncService.deviceName,
            "id": syncService.deviceId,
            "ip": syncService.localIPAddress,
            "port": syncService.port,
            "version": Bundle.main.appVersion
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: info),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "LocalPeerSync://connect"
        }
        
        return "LocalPeerSync://connect?\(jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("Share Connection")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Scan this QR code from another device to connect instantly")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // QR Code
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(width: 250, height: 250)
                    } else if let qrImage = qrCodeImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray5))
                            .frame(width: 250, height: 250)
                            .overlay(
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.title)
                                        .foregroundColor(.orange)
                                    Text("Failed to generate QR code")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                    
                    Text("Device: \(syncService.deviceName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Connection Details
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connection Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 8) {
                        ConnectionDetailRow(label: "Device Name", value: syncService.deviceName)
                        ConnectionDetailRow(label: "IP Address", value: syncService.localIPAddress)
                        ConnectionDetailRow(label: "Port", value: "\(syncService.port)")
                        ConnectionDetailRow(label: "Status", value: syncService.isRunning ? "Online" : "Offline")
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share QR Code")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(qrCodeImage == nil)
                    
                    Button(action: {
                        generateQRCode()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.regularMaterial)
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
            .navigationTitle("Share Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            generateQRCode()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let qrImage = qrCodeImage {
                ShareSheet(items: [qrImage, connectionInfo])
            }
        }
    }
    
    private func generateQRCode() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(connectionInfo.utf8)
            filter.correctionLevel = "M"
            
            if let outputImage = filter.outputImage {
                // Scale up the QR code for better quality
                let scaleX = 250 / outputImage.extent.size.width
                let scaleY = 250 / outputImage.extent.size.height
                let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                
                if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    
                    DispatchQueue.main.async {
                        self.qrCodeImage = uiImage
                        self.isLoading = false
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                self.qrCodeImage = nil
                self.isLoading = false
            }
        }
    }
}

struct ConnectionDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(minWidth: 80, alignment: .leading)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    QRCodeSharingView()
        .environmentObject(SyncService.shared)
}
