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
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // MARK: - Chat Messages ScrollView
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 8) {
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
                                            .id("typing-indicator")
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .onAppear {
                                scrollToBottom(proxy: proxy)
                            }
                            .onChange(of: viewModel.messages.count) { _, _ in
                                scrollToBottom(proxy: proxy)
                            }
                        }
                        
                        // MARK: - Recording Text Preview
                        if viewModel.isRecording && !viewModel.recognizedText.isEmpty {
                            HStack {
                                Text(viewModel.recognizedText)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color(red: 0.17, green: 0.17, blue: 0.18))
                                    )
                                    .frame(maxWidth: geometry.size.width * 0.75, alignment: .leading)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // MARK: - Attachment Thumbnail
                        if viewModel.currentAttachment != nil {
                            AttachmentThumbnailView()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // MARK: - Bottom Input Bar
                        HStack(spacing: 12) {
                            AttachmentButton()
                            
                            Spacer()
                            
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
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
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
    
    // MARK: - Scroll Helper
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
    
    // MARK: - Test Connection
    private func testOpenAIConnection() {
        print("🧪 TEST: Starting OpenAI connection test")
        
        Task {
            do {
                print("🧪 TEST: Calling OpenAI with test message")
                let response = try await OpenAIService.shared.sendChatMessage(
                    messages: [Message(content: "Say hello", isFromUser: true)],
                    systemPrompt: "You are Ray. Say hello back."
                )
                print("🧪 TEST RESPONSE: \(response)")
                
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
                
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(message.isFromUser ?
                                      Color(red: 0.0, green: 0.48, blue: 1.0) :
                                      Color(red: 0.23, green: 0.23, blue: 0.24)
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
                
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
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
            Button {
                UIPasteboard.general.string = message.content
                showCopiedFeedback = true
                
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
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
            
            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                TextToSpeechService.shared.speak(text: message.content)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2")
                    Text("Read")
                        .font(.caption)
                }
                .foregroundColor(.gray)
            }
            
            Button {
                shareMessage(message.content)
                showSharedFeedback = true
                
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
}

// MARK: - Typing Indicator Bubble

struct TypingIndicatorBubble: View {
    @State private var isAnimating = false
    
    private let bubbleBackground = Color.gray.opacity(0.2)
    private let dotColor = Color.gray.opacity(0.6)
    private let dotSize: CGFloat = 8
    private let animationDuration = 0.6
    
    var body: some View {
        HStack(alignment: .bottom) {
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
