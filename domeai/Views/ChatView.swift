//
//  ChatView.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var micButtonScale: CGFloat = 1.0
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Black background
                    Color.black
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Main chat area
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(viewModel.messages) { message in
                                        MessageBubble(message: message, maxWidth: geometry.size.width * 0.75)
                                            .id(message.id)
                                            .transition(.asymmetric(
                                                insertion: .move(edge: message.isFromUser ? .trailing : .leading)
                                                    .combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                    }
                                    
                                    // Ray is thinking indicator with animated dots
                                    if viewModel.isProcessing {
                                        RayThinkingIndicator()
                                            .id("thinking")
                                            .transition(.opacity)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .onChange(of: viewModel.messages.count) { _, _ in
                                if let lastMessage = viewModel.messages.last {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                            .onChange(of: viewModel.isProcessing) { _, isProcessing in
                                if isProcessing {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            proxy.scrollTo("thinking", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Recognized text bubble while recording
                        if viewModel.isRecording && !viewModel.recognizedText.isEmpty {
                            HStack {
                                Text(viewModel.recognizedText)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color(red: 0.17, green: 0.17, blue: 0.18)) // #3A3A3C
                                    )
                                    .frame(maxWidth: geometry.size.width * 0.75, alignment: .leading)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // Attachment Thumbnail (just above input bar)
                        if viewModel.currentAttachment != nil {
                            AttachmentThumbnailView()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // Bottom input area
                        HStack(spacing: 12) {
                            // Paperclip button
                            AttachmentButton()
                            
                            Spacer()
                            
                            // Microphone button
                            Button {
                                toggleRecording()
                            } label: {
                                Circle()
                                    .fill(viewModel.isRecording ? Color.red : Color.blue)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Image(systemName: "mic.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 20, weight: .medium))
                                    )
                                    .scaleEffect(micButtonScale)
                            }
                            .disabled(viewModel.isProcessing)
                            .opacity(viewModel.isProcessing ? 0.5 : 1.0)
                            .onAppear {
                                updateMicAnimation()
                            }
                            .onChange(of: viewModel.isRecording) { _, _ in
                                updateMicAnimation()
                            }
                        }
                        .frame(height: 60)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            Color(red: 0.11, green: 0.11, blue: 0.12) // Dark gray input bar
                        )
                    }
                }
                .navigationTitle("Ray 💬")
                .navigationBarTitleDisplayMode(.inline)
                .preferredColorScheme(.dark)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            testOpenAIConnection()
                        } label: {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
    }
    
    // Test function for direct API testing
    private func testOpenAIConnection() {
        print("🧪 TEST: Starting OpenAI connection test")
        // Config.testKeys() // Removed - debug function no longer needed
        
        Task {
            do {
                print("🧪 TEST: Calling OpenAI with test message")
                let response = try await OpenAIService.shared.sendChatMessage(
                    messages: [Message(content: "Say hello", isFromUser: true)],
                    systemPrompt: "You are Ray. Say hello back."
                )
                print("🧪 TEST RESPONSE: \(response)")
                
                // Add test response to chat
                await MainActor.run {
                    let testMessage = Message(content: "🧪 TEST: \(response)", isFromUser: false)
                    viewModel.messages.append(testMessage)
                }
            } catch {
                print("🧪 TEST ERROR: \(error.localizedDescription)")
                print("🧪 TEST ERROR: Full error: \(error)")
            }
        }
    }
    
    private func toggleRecording() {
        if viewModel.isRecording {
            viewModel.stopVoiceInput()
        } else {
            viewModel.startVoiceInput()
        }
    }
    
    private func updateMicAnimation() {
        if viewModel.isRecording {
            withAnimation(
                Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
            ) {
                micButtonScale = 1.1
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                micButtonScale = 1.0
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    var maxWidth: CGFloat = 300
    
    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer()
            }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                // Display image if present
                if let imageData = message.attachmentData,
                   message.attachmentType == "image",
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxWidth, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 4)
                }
                
                // Display text content
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(message.isFromUser ? 
                                      Color(red: 0.0, green: 0.48, blue: 1.0) : // #007AFF
                                      Color(red: 0.23, green: 0.23, blue: 0.24)  // #3A3A3C
                                )
                        )
                        .frame(maxWidth: maxWidth, alignment: message.isFromUser ? .trailing : .leading)
                }
            }
            
            if !message.isFromUser {
                Spacer()
            }
        }
    }
}

// MARK: - User Message Actions

struct UserMessageActions: View {
    let message: Message
    @State private var showCopiedFeedback = false
    
    var body: some View {
        HStack {
            Spacer()
            
            Button {
                UIPasteboard.general.string = message.content
                showCopiedFeedback = true
                
                // Haptic feedback
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                // Reset after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopiedFeedback = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                    Text(showCopiedFeedback ? "Copied!" : "Copy")
                        .font(.caption)
                }
                .foregroundColor(showCopiedFeedback ? .green : .gray)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Ray Message Actions

struct RayMessageActions: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    @Binding var messageText: String
    @State private var showCopiedFeedback = false
    @State private var showSharedFeedback = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Copy button
            Button {
                UIPasteboard.general.string = message.content
                showCopiedFeedback = true
                
                // Haptic feedback
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                // Reset after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopiedFeedback = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                    Text(showCopiedFeedback ? "Copied!" : "Copy")
                        .font(.caption)
                }
                .foregroundColor(showCopiedFeedback ? .green : .gray)
            }
            
            // Read aloud button
            Button {
                // Haptic feedback
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                // Read aloud
                TextToSpeechService.shared.speak(text: message.content)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2")
                    Text("Read")
                        .font(.caption)
                }
                .foregroundColor(.gray)
            }
            
            // Share button
            Button {
                shareMessage(message.content)
                showSharedFeedback = true
                
                // Haptic feedback
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showSharedFeedback = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showSharedFeedback ? "checkmark" : "square.and.arrow.up")
                    Text(showSharedFeedback ? "Shared!" : "Share")
                        .font(.caption)
                }
                .foregroundColor(showSharedFeedback ? .green : .gray)
            }
            
            // Sources button (only if message has sources)
            if let sources = message.sources, !sources.isEmpty {
                Button {
                    viewModel.showSources(for: message)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Sources (\(sources.count))")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.leading, message.isFromUser ? 0 : 50)
        .padding(.trailing, message.isFromUser ? 50 : 0)
        .padding(.top, 4)
    }
    
    private func shareMessage(_ text: String) {
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(av, animated: true)
        }
    }
    
    private func findPreviousUserMessage(for rayMessage: Message) -> Message? {
        // Find the user message that generated this Ray response
        // It should be the last user message before this Ray message
        guard let rayIndex = viewModel.messages.firstIndex(where: { $0.id == rayMessage.id }) else {
            return nil
        }
        
        // Look backwards from the Ray message to find the previous user message
        for i in (0..<rayIndex).reversed() {
            if viewModel.messages[i].isFromUser {
                return viewModel.messages[i]
            }
        }
        
        return nil
    }
}

// MARK: - Ray Thinking Indicator

struct RayThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Ray is thinking")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.gray)
            
            HStack(spacing: 4) {
                ThinkingDot(animationDelay: 0.0)
                ThinkingDot(animationDelay: 0.2)
                ThinkingDot(animationDelay: 0.4)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ThinkingDot: View {
    let animationDelay: Double
    @State private var opacity: Double = 0.3
    
    var body: some View {
        Circle()
            .fill(Color.gray)
            .frame(width: 6, height: 6)
            .opacity(opacity)
            .onAppear {
                startPulsingAnimation()
            }
    }
    
    private func startPulsingAnimation() {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(animationDelay * 1_000_000_000))
            
            while true {
                withAnimation(.easeInOut(duration: 0.5)) {
                    opacity = 1.0
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                withAnimation(.easeInOut(duration: 0.5)) {
                    opacity = 0.3
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatViewModel())
}
