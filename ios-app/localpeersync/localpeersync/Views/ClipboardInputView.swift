//
//  ClipboardInputView.swift
//  LocalPeerSync
//
//  Manual clipboard input interface
//

import SwiftUI

struct ClipboardInputView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var inputText: String = ""
    @State private var showingSuccessAnimation = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                        .scaleEffect(showingSuccessAnimation ? 1.2 : 1.0)
                        .animation(.bouncy, value: showingSuccessAnimation)
                    
                    Text("Add to Clipboard")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Enter text to add to your clipboard and sync across devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Text Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    TextEditor(text: $inputText)
                        .focused($isTextFieldFocused)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isTextFieldFocused ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    
                    HStack {
                        Text("\(inputText.count) characters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if inputText.count > 1000 {
                            Label("Large content", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        QuickActionButton(
                            icon: "link",
                            title: "Paste URL",
                            color: .purple
                        ) {
                            if let url = UIPasteboard.general.string, url.isValidURL {
                                inputText = url
                                HapticFeedback.light()
                            }
                        }
                        
                        QuickActionButton(
                            icon: "doc.on.clipboard",
                            title: "Paste Current",
                            color: .blue
                        ) {
                            if let current = UIPasteboard.general.string {
                                inputText = current
                                HapticFeedback.light()
                            }
                        }
                        
                        QuickActionButton(
                            icon: "trash",
                            title: "Clear",
                            color: .red
                        ) {
                            inputText = ""
                            HapticFeedback.light()
                        }
                        
                        QuickActionButton(
                            icon: "clock.arrow.circlepath",
                            title: "History",
                            color: .orange
                        ) {
                            // Show history picker
                            HapticFeedback.light()
                        }
                    }
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: addToClipboard) {
                        HStack {
                            if showingSuccessAnimation {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.headline)
                            }
                            
                            Text(showingSuccessAnimation ? "Added!" : "Add to Clipboard")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(showingSuccessAnimation ? Color.green : Color.blue)
                        )
                        .foregroundColor(.white)
                        .scaleEffect(showingSuccessAnimation ? 1.05 : 1.0)
                        .animation(.bouncy, value: showingSuccessAnimation)
                    }
                    .disabled(inputText.trimmed().isEmpty || showingSuccessAnimation)
                    
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("Add Content")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    private func addToClipboard() {
        let trimmedText = inputText.trimmed()
        guard !trimmedText.isEmpty else { return }
        
        clipboardManager.addTextToClipboard(trimmedText)
        
        withAnimation(.bouncy) {
            showingSuccessAnimation = true
        }
        
        HapticFeedback.success()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ClipboardInputView()
        .environmentObject(ClipboardManager.shared)
}
