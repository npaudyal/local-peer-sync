//
//  DeviceRenameView.swift
//  LocalPeerSync
//

import SwiftUI

struct DeviceRenameView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var newName: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Device Name", text: $newName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button("Save") {
                    // Save new name
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .navigationTitle("Rename Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
