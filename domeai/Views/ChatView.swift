//
//  ChatView.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI
import UIKit
import Combine

struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var micButtonScale: CGFloat = 1.0
    @State private var pendingDeleteMessage: Message? = nil
    @State private var showScrollButton = false
    @State private var hasScrolledToBottom = false
    
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
                            VStack(spacing: 0) {
                                ScrollView {
                                    VStack(spacing: 8) {
                                        ForEach(viewModel.messages) { message in
                                            let index = viewModel.messages.firstIndex(where: { $0.id == message.id }) ?? 0
                                            MessageWithTimestampView(
                                                message: message,
                                                previousMessage: index > 0 ? viewModel.messages[index - 1] : nil,
                                                maxWidth: geometry.size.width * 0.75
                                            )
                                            .id(message.id)
                                        }
                                        
                                        if viewModel.isProcessing {
                                            TypingIndicatorBubble()
                                                .id("thinking")
                                        }
                                        
                                        Color.clear
                                            .frame(height: 1)
                                            .id("BOTTOM_ANCHOR")
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .defaultScrollAnchor(.bottom)
                                .onAppear {
                                    proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                                }
                                .onReceive(Just(viewModel.messages.count)) { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                                    }
                                }
                            }
                            .overlay(alignment: .bottom) {
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(Color.blue))
                                        .shadow(radius: 4)
                                }
                                .padding(.bottom, 80)
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

private struct MessageBubble: View {
    let message: Message
    var maxWidth: CGFloat = 300
    @State private var showCopiedToast = false
    
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
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                provideHapticFeedback()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCopiedToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCopiedToast = false
                    }
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .overlay(alignment: message.isFromUser ? .topTrailing : .topLeading) {
            if showCopiedToast {
                Text("Copied!")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .scale))
                    .padding(message.isFromUser ? .trailing : .leading, 8)
            }
        }
    }
    
    private func provideHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Timestamp Wrapper

/// Wraps a message bubble with an optional timestamp shown when enough time passed since previous message.
private struct MessageWithTimestampView: View {
    let message: Message
    let previousMessage: Message?
    let maxWidth: CGFloat
    
    var body: some View {
        VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
            MessageBubble(message: message, maxWidth: maxWidth)
                .transition(.asymmetric(
                    insertion: .move(edge: message.isFromUser ? .trailing : .leading)
                        .combined(with: .opacity),
                    removal: .opacity
                ))
            
            if shouldShowTimestamp {
                Text(message.timestamp, style: .relative)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.gray)
                    .opacity(0.7)
                    .frame(maxWidth: maxWidth, alignment: message.isFromUser ? .trailing : .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isFromUser ? .trailing : .leading)
        .padding(.horizontal, 4)
    }
    
    /// Only show timestamp when >5 minutes elapsed since previous message.
    private var shouldShowTimestamp: Bool {
        guard let previous = previousMessage else { return true }
        let difference = message.timestamp.timeIntervalSince(previous.timestamp)
        return difference >= 5 * 60
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

// MARK: - Typing Indicator Bubble

/// Animated typing bubble that mimics modern chat apps while Ray is processing.
struct TypingIndicatorBubble: View {
    @State private var isAnimating = false
    
    private let bubbleBackground = Color.gray.opacity(0.2)
    private let dotColor = Color.gray.opacity(0.6)
    private let dotSize: CGFloat = 8
    private let animationDuration = 0.6
    
    var body: some View {
        HStack(alignment: .bottom) {
            // Align to left like Ray's messages
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        TypingDot(
                            delay: Double(index) * (animationDuration / 3),
                            isAnimating: $isAnimating,
                            size: dotSize,
                            color: dotColor,
                            duration: animationDuration
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    // Ray-style light bubble with rounded corners
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(bubbleBackground)
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                )
                .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: .leading)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

/// Single animated dot used in the typing indicator.
private struct TypingDot: View {
    let delay: Double
    @Binding var isAnimating: Bool
    let size: CGFloat
    let color: Color
    let duration: Double

    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: isAnimating) { _, animating in
                if animating {
                    startAnimating()
                } else {
                    stopAnimating()
                }
            }
            .onAppear {
                if isAnimating {
                    startAnimating()
                }
            }
    }

    private func startAnimating() {
        withAnimation(
            Animation.easeInOut(duration: duration)
                .repeatForever()
                .delay(delay)
        ) {
            scale = 1.0
            opacity = 1.0
        }
    }

    private func stopAnimating() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 0.8
            opacity = 0.6
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatViewModel())
}
