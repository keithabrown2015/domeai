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
                        // FLIPPED SCROLLVIEW - This makes it open at bottom
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                // REVERSED message order because view is flipped
                                ForEach(viewModel.messages.reversed()) { message in
                                    let originalIndex = viewModel.messages.firstIndex(where: { $0.id == message.id }) ?? 0
                                    let previousMessage = originalIndex > 0 ? viewModel.messages[originalIndex - 1] : nil
                                    
                                    MessageWithTimestampView(
                                        message: message,
                                        previousMessage: previousMessage,
                                        maxWidth: geometry.size.width * 0.75
                                    )
                                    .rotationEffect(.degrees(180))
                                    .scaleEffect(x: -1, y: 1, anchor: .center)
                                    .id(message.id)
                                }
                                
                                if viewModel.isProcessing {
                                    TypingIndicatorBubble()
                                        .rotationEffect(.degrees(180))
                                        .scaleEffect(x: -1, y: 1, anchor: .center)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .rotationEffect(.degrees(180))
                        .scaleEffect(x: -1, y: 1, anchor: .center)
                        
                        // Recording text bubble
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
                        
                        // Attachment thumbnail
                        if viewModel.currentAttachment != nil {
                            AttachmentThumbnailView()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // Bottom input bar
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
                            .onAppear { updateMicAnimation() }
                            .onChange(of: viewModel.isRecording) { _, _ in updateMicAnimation() }
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
    
    private func testOpenAIConnection() {
        Task {
            do {
                let response = try await OpenAIService.shared.sendChatMessage(
                    messages: [Message(content: "Say hello", isFromUser: true)],
                    systemPrompt: "You are Ray. Say hello back."
                )
                await MainActor.run {
                    let testMessage = Message(content: "🧪 TEST: \(response)", isFromUser: false)
                    viewModel.messages.append(testMessage)
                }
            } catch {
                print("🧪 TEST ERROR: \(error)")
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
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                micButtonScale = 1.1
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                micButtonScale = 1.0
            }
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    var maxWidth: CGFloat = 300
    @State private var showCopiedToast = false
    
    var body: some View {
        HStack {
            if message.isFromUser { Spacer() }
            
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
                                      Color(red: 0.23, green: 0.23, blue: 0.24))
                        )
                        .frame(maxWidth: maxWidth, alignment: message.isFromUser ? .trailing : .leading)
                }
            }
            
            if !message.isFromUser { Spacer() }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

private struct MessageWithTimestampView: View {
    let message: Message
    let previousMessage: Message?
    let maxWidth: CGFloat
    
    var body: some View {
        VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
            MessageBubble(message: message, maxWidth: maxWidth)
            
            if shouldShowTimestamp {
                Text(message.timestamp, style: .relative)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.gray)
                    .opacity(0.7)
                    .frame(maxWidth: maxWidth, alignment: message.isFromUser ? .trailing : .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isFromUser ? .trailing : .leading)
        .padding(.horizontal, 4)
    }
    
    private var shouldShowTimestamp: Bool {
        guard let previous = previousMessage else { return true }
        return message.timestamp.timeIntervalSince(previous.timestamp) >= 5 * 60
    }
}

struct TypingIndicatorBubble: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0.6)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.2),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.gray.opacity(0.2)))
            Spacer()
        }
        .padding(.horizontal, 16)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatViewModel())
}
