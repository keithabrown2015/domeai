//
//  HomeView.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var userSettings: UserSettings
    @ObservedObject var ttsService = TextToSpeechService.shared
    @State private var selectedCategory: MemoryCategory?
    @State private var messageText: String = ""
    @State private var showingAttachmentSheet = false
    @State private var showingEmailSettings = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var selectedSection: String = "" // Default to empty so chat shows on launch
    @FocusState private var isTextFieldFocused: Bool
    
    // Scroll to bottom button state
    @State private var isUserScrolling = false
    @State private var showScrollButton = false
    @State private var scrollProxy: ScrollViewProxy?
    
    // Emoji reordering state
    @State private var emojiOrder = ["🧠", "⏰", "📅", "🏃", "💊", "🩺", "🔗"]
    @State private var draggedEmoji: String?
    
    // Attachment picker states
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var showingDocuments = false
    @State private var selectedImage: UIImage? = nil
    @State private var selectedDocumentURL: URL? = nil
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 0) {
                            EmojiNavRow(
                                selectedSection: $selectedSection,
                                emojiOrder: $emojiOrder,
                                draggedEmoji: $draggedEmoji
                            )
                            .environmentObject(chatViewModel)
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                            .padding(.horizontal, 16)
                            
                            // Show different content based on selected section
                            // Default (empty string) shows chat view
                            if selectedSection == "🧠" {
                                NavigationStack {
                                    BrainView(onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            selectedSection = ""
                                        }
                                    })
                                    .navigationBarTitleDisplayMode(.inline)
                                }
                            } else if selectedSection == "⏰" {
                                NavigationStack {
                                    ComingSoonView(onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            selectedSection = ""
                                        }
                                    }, emoji: "⏰", title: "Nudges")
                                }
                            } else if selectedSection == "📅" {
                                NavigationStack {
                                    ComingSoonView(onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            selectedSection = ""
                                        }
                                    }, emoji: "📅", title: "Calendar")
                                }
                            } else if selectedSection == "💊" {
                                NavigationStack {
                                    ComingSoonView(onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            selectedSection = ""
                                        }
                                    }, emoji: "💊", title: "Meds")
                                }
                            } else if selectedSection == "🏃" {
                                NavigationStack {
                                    ComingSoonView(onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            selectedSection = ""
                                        }
                                    }, emoji: "🏃", title: "Exercise")
                                }
                            } else if selectedSection == "🩺" {
                                NavigationStack {
                                    ComingSoonView(onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            selectedSection = ""
                                        }
                                    }, emoji: "🩺", title: "Health")
                                }
                            } else if selectedSection == "🔗" {
                                NavigationStack {
                                    ComingSoonView(onDismiss: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            selectedSection = ""
                                        }
                                    }, emoji: "🔗", title: "Links")
                                }
                            } else {
                                // Default: show chat (when selectedSection is empty or other emoji)
                                chatMessagesSection(geometry)
                                attachmentSection
                                bottomInputBar
                            }
                        }
                    )
                    .overlay(ttsOverlay, alignment: .top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Only show help button when on chat screen (selectedSection is empty)
                    if selectedSection.isEmpty {
                        Button {
                            // Help button action
                        } label: {
                            Text("❓")
                                .font(.system(size: 20))
                        }
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Image("DomeLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)  // 2x bigger
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingEmailSettings = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationDestination(item: $selectedCategory) { category in
                MemoryDetailView(category: category)
            }
            .confirmationDialog("Add Attachment", isPresented: $showingAttachmentSheet, titleVisibility: .visible) {
                Button("Camera") {
                    requestCameraPermission()
                }
                Button("Photo Library") {
                    imagePickerSourceType = .photoLibrary
                    showingPhotoLibrary = true
                }
                Button("Documents") {
                    showingDocuments = true
                }
                Button("Cancel", role: .cancel) {
                    showingAttachmentSheet = false
                }
            }
            .sheet(isPresented: $showingCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                ImagePicker(sourceType: imagePickerSourceType, selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showingDocuments) {
                DocumentPicker()
                    .environmentObject(chatViewModel)
            }
            .sheet(isPresented: $chatViewModel.showingSourcesSheet) {
                NavigationView {
                    List(chatViewModel.selectedMessageSources) { source in
                        Button {
                            if let url = URL(string: source.url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(source.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                
                                Text(source.url)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .navigationTitle("Sources (\(chatViewModel.selectedMessageSources.count))")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                chatViewModel.showingSourcesSheet = false
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedImage) { _, newImage in
                if let image = newImage {
                    handleImageSelection(image)
                }
            }
            .onAppear {
                loadEmojiOrder()
            }
            .onChange(of: emojiOrder) { _, _ in
                saveEmojiOrder()
            }
        }
    }
    
    // MARK: - Emoji Order Persistence
    
    private func saveEmojiOrder() {
        UserDefaults.standard.set(emojiOrder, forKey: "emojiOrder")
    }
    
    private func loadEmojiOrder() {
        if let saved = UserDefaults.standard.stringArray(forKey: "emojiOrder") {
            emojiOrder = saved
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || chatViewModel.currentAttachment != nil else { return }
        
        chatViewModel.sendMessage(content: text)
        messageText = ""
        isTextFieldFocused = false  // Dismiss keyboard immediately
    }
    
    private func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            imagePickerSourceType = .camera
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        imagePickerSourceType = .camera
                        showingCamera = true
                    }
                }
            }
        default:
            print("⚠️ Camera access denied")
        }
        showingAttachmentSheet = false
    }
    
    private func handleImageSelection(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert image to data")
            return
        }
        
        let fileName = imagePickerSourceType == .camera 
            ? "camera_\(UUID().uuidString.prefix(8)).jpg"
            : "photo_\(UUID().uuidString.prefix(8)).jpg"
        
        let attachment = AttachmentService.shared.createAttachment(
            type: .photo,
            data: imageData,
            fileName: fileName
        )
        chatViewModel.attachFile(attachment)
        selectedImage = nil // Reset for next selection
    }
    
    private func toggleRecording() {
        if chatViewModel.isRecording {
            chatViewModel.stopVoiceInput()
        } else {
            chatViewModel.startVoiceInput()
        }
    }
    
    private func updatePulseAnimation() {
        if chatViewModel.isRecording {
            withAnimation(
                Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.2
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                pulseScale = 1.0
            }
        }
    }
    
    @ViewBuilder
    private func chatMessagesSection(_ geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Top spacer to help with scroll detection
                        Color.clear
                            .frame(height: 1)
                            .id("top")
                        
                        ForEach(chatViewModel.messages) { message in
                            messageRow(for: message, geometry: geometry)
                                .id(message.id)
                        }
                        
                        if chatViewModel.isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .padding(.top, 12)
                                .id("thinking")
                        }
                        
                        // Bottom marker for scroll detection
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ViewOffsetKey.self,
                                        value: geo.frame(in: .named("scroll")).minY
                                    )
                                }
                            )
                    }
                    .padding()
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ViewOffsetKey.self) { offset in
                    // Debug: Print offset to see what values we're getting
                    print("🔍 Scroll offset: \(offset)")
                    
                    // When at bottom, offset should be close to 0 or positive
                    // When scrolled up, offset becomes more negative
                    // Show button when scrolled up more than 100 points
                    let shouldShow = offset < -100
                    print("🔍 Should show scroll button: \(shouldShow), current showScrollButton: \(showScrollButton)")
                    
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScrollButton = shouldShow
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: chatViewModel.messages.count) { _, _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    // Hide button when new message arrives and auto-scrolls
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollButton = false
                        }
                    }
                }
            }
            
            // Floating scroll to bottom button - MUST be last in ZStack to render on top
            // TEMPORARY: Always show for debugging
            Button {
                print("🔍 Scroll button tapped!")
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    scrollProxy?.scrollTo("bottom", anchor: .bottom)
                }
                // Hide button after scrolling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScrollButton = false
                    }
                }
            } label: {
                ZStack {
                    // TEMPORARY: Bright red background for debugging visibility
                    Circle()
                        .fill(Color.red.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
                    
                    // Down arrow icon
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 100) // Position above input bar
            .opacity(showScrollButton ? 1.0 : 0.0) // Fade based on state
            .allowsHitTesting(showScrollButton) // Only tappable when visible
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .zIndex(1000) // Ensure it's on top
        }
        .onChange(of: showScrollButton) { oldValue, newValue in
            print("🔍 showScrollButton changed: \(oldValue) -> \(newValue)")
        }
        .overlay(alignment: .bottom) {
            // Floating scroll to bottom button - centered above input field
            if showScrollButton {
                Button(action: {
                    print("ARROW TAPPED - Scrolling to bottom")
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        scrollProxy?.scrollTo("bottom", anchor: .bottom)
                    }
                    // Hide button after scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollButton = false
                        }
                    }
                }) {
                    ZStack {
                        // iOS-style blur background
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
                        
                        // Down arrow icon
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.bottom, 70) // Position just above input field
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }
    
    @ViewBuilder
    private func messageRow(for message: Message, geometry: GeometryProxy) -> some View {
        VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                if message.isFromUser { Spacer(minLength: 0) }
                
                VStack(alignment: .leading, spacing: 6) {
                    if let imageData = message.attachmentData,
                       message.attachmentType == "image",
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geometry.size.width * 0.65, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(message.isFromUser ? .white : .primary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.isFromUser ? Color.blue.opacity(0.85) : Color.gray.opacity(0.2))
                )
                .frame(maxWidth: geometry.size.width * 0.75, alignment: message.isFromUser ? .trailing : .leading)
                
                if !message.isFromUser { Spacer(minLength: 0) }
            }
            
            MessageActionButtons(message: message, viewModel: chatViewModel)
        }
    }
    
    @ViewBuilder
    private var attachmentSection: some View {
        if chatViewModel.currentAttachment != nil {
            AttachmentRowView()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private var bottomInputBar: some View {
        HStack(spacing: 12) {
            Button {
                showingAttachmentSheet = true
            } label: {
                Text("📎")
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
            }
            
            TextField("Message Ray...", text: $messageText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(12)
                .background(
                    Capsule()
                        .fill(Color(red: 0.17, green: 0.17, blue: 0.18))
                )
                .focused($isTextFieldFocused)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.sentences)
                .keyboardType(.default)
                .submitLabel(.send)
                .disabled(chatViewModel.isProcessing)
                .onSubmit { sendMessage() }
                .animation(.easeInOut(duration: 0.2), value: isTextFieldFocused)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            
            Button {
                toggleRecording()
            } label: {
                ZStack {
                    if chatViewModel.isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.6), lineWidth: 3)
                            .frame(width: 60, height: 60)
                            .scaleEffect(pulseScale)
                            .opacity(pulseScale > 1.0 ? 0.3 : 0.6)
                    }
                    
                    Text("🎙️")
                        .font(.system(size: 32))
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(chatViewModel.isRecording ? Color.red.opacity(0.3) : Color.clear)
                        )
                }
            }
            .disabled(chatViewModel.isProcessing)
            .opacity(chatViewModel.isProcessing ? 0.5 : 1.0)
            .onAppear {
                updatePulseAnimation()
            }
            .onChange(of: chatViewModel.isRecording) { _, _ in
                updatePulseAnimation()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }
    
    @ViewBuilder
    private var ttsOverlay: some View {
        if ttsService.isSpeaking || ttsService.isPaused {
            VStack {
                HStack(spacing: 20) {
                    Text("Ray is speaking...")
                        .foregroundColor(.white)
                        .font(.callout)
                    
                    Button {
                        if ttsService.isPaused {
                            ttsService.resume()
                        } else {
                            ttsService.pause()
                        }
                    } label: {
                        Image(systemName: ttsService.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    
                    Button {
                        ttsService.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.black.opacity(0.85))
                )
                .shadow(radius: 10)
                
                Spacer()
            }
            .padding(.top, 100)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(), value: ttsService.isSpeaking || ttsService.isPaused)
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
                    chatViewModel.messages.append(testMessage)
                }
            } catch {
                print("🧪 TEST ERROR: \(error.localizedDescription)")
                print("🧪 TEST ERROR: Full error: \(error)")
            }
        }
    }
    
}

// MARK: - Attachment Row View

struct AttachmentRowView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    
    var body: some View {
        if let attachment = viewModel.currentAttachment {
            HStack(spacing: 12) {
                // Origin emoji based on type
                Text(attachment.type == .photo ? (attachment.fileName.contains("camera") ? "📷" : "🖼️") : "📁")
                    .font(.system(size: 20))
                
                // Thumbnail
                if let thumbnail = attachment.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // File name
                Text(attachment.fileName)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                // Remove button
                Button {
                    viewModel.removeAttachment()
                } label: {
                    Text("✖︎")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.23, green: 0.23, blue: 0.24))
            )
        }
    }
}



// MARK: - Attachment Sheet Trigger

struct AttachmentSheetTrigger: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var viewModel: ChatViewModel
    
    var body: some View {
        AttachmentActionSheet(isPresented: $isPresented)
            .environmentObject(viewModel)
    }
}

// MARK: - Attachment Action Sheet

struct AttachmentActionSheet: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var showingActionSheet = false
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImage: UIImage?
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingActionSheet = true
                }
            }
            .confirmationDialog("Add Attachment", isPresented: $showingActionSheet, titleVisibility: .visible) {
                Button("Camera") {
                    requestCameraPermission()
                }
                Button("Photo Library") {
                    imagePickerSourceType = .photoLibrary
                    showingImagePicker = true
                }
                Button("Documents") {
                    showingDocumentPicker = true
                }
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(sourceType: imagePickerSourceType, selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker()
                    .environmentObject(viewModel)
            }
            .onChange(of: selectedImage) { _, newImage in
                if let newImage = newImage, let imageData = newImage.jpegData(compressionQuality: 0.8) {
                    let attachment = AttachmentService.shared.createAttachment(
                        type: .photo,
                        data: imageData,
                        fileName: "photo_\(UUID().uuidString.prefix(8)).jpg"
                    )
                    viewModel.attachFile(attachment)
                    selectedImage = nil
                    isPresented = false
                }
            }
            .onChange(of: showingActionSheet) { _, newValue in
                if !newValue {
                    isPresented = false
                }
            }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    imagePickerSourceType = .camera
                    showingImagePicker = true
                }
            }
        }
    }
}

// MARK: - Emoji Navigation Row

struct EmojiNavRow: View {
    @Binding var selectedSection: String
    @Binding var emojiOrder: [String]
    @Binding var draggedEmoji: String?
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImage: UIImage?
    @State private var attachmentEmojis = ["📷", "🖼️", "📁"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(emojiOrder, id: \.self) { emoji in
                    EmojiButton(
                        emoji: emoji,
                        isSelected: selectedSection == emoji,
                        isAttachment: attachmentEmojis.contains(emoji)
                    ) {
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        
                        // Handle attachment emojis
                        if attachmentEmojis.contains(emoji) {
                            handleAttachmentTap(emoji: emoji)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                selectedSection = emoji
                            }
                        }
                    }
                    .onDrag {
                        draggedEmoji = emoji
                        return NSItemProvider(object: emoji as NSString)
                    }
                    .onDrop(of: [.text], delegate: EmojiDropDelegate(
                        emoji: emoji,
                        emojiOrder: $emojiOrder,
                        draggedEmoji: $draggedEmoji
                    ))
                }
            }
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: imagePickerSourceType, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPickerMultiSelect(maxFiles: 3)
                .environmentObject(viewModel)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let newImage = newImage, let imageData = newImage.jpegData(compressionQuality: 0.8) {
                let fileName = imagePickerSourceType == .camera ? "camera_\(UUID().uuidString.prefix(8)).jpg" : "photo_\(UUID().uuidString.prefix(8)).jpg"
                let attachment = AttachmentService.shared.createAttachment(
                    type: .photo,
                    data: imageData,
                    fileName: fileName
                )
                viewModel.attachFile(attachment)
                selectedImage = nil
            }
        }
    }
    
    private func handleAttachmentTap(emoji: String) {
        switch emoji {
        case "📷":
            // Camera
            requestCameraPermission()
        case "🖼️":
            // Photo Library
            imagePickerSourceType = .photoLibrary
            showingImagePicker = true
        case "📁":
            // Documents
            showingDocumentPicker = true
        default:
            break
        }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    imagePickerSourceType = .camera
                    showingImagePicker = true
                }
            }
        }
    }
}

// MARK: - Emoji Button

struct EmojiButton: View {
    let emoji: String
    let isSelected: Bool
    let isAttachment: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Dark gray circle background when selected
                if isSelected {
                    Circle()
                        .fill(Color(red: 0.23, green: 0.23, blue: 0.24)) // Dark gray
                        .frame(width: 50, height: 50)
                }
                
                // Emoji
                Text(emoji)
                    .font(.system(size: 32))
                    .frame(width: 50, height: 50)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Document Picker Multi-Select (for 📁 emoji)

struct DocumentPickerMultiSelect: UIViewControllerRepresentable {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    let maxFiles: Int
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .data], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, viewModel: viewModel, maxFiles: maxFiles)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerMultiSelect
        weak var viewModel: ChatViewModel?
        let maxFiles: Int
        
        init(_ parent: DocumentPickerMultiSelect, viewModel: ChatViewModel, maxFiles: Int) {
            self.parent = parent
            self.viewModel = viewModel
            self.maxFiles = maxFiles
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let selectedUrls = Array(urls.prefix(maxFiles))
            
            for url in selectedUrls {
                guard url.startAccessingSecurityScopedResource() else {
                    print("❌ Failed to access security-scoped resource: \(url.lastPathComponent)")
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                do {
                    let data = try Data(contentsOf: url)
                    let fileName = url.lastPathComponent
                    
                    // Check file type
                    let fileExtension = (fileName as NSString).pathExtension.lowercased()
                    let isPDF = fileExtension == "pdf"
                    let isDOCX = fileExtension == "docx"
                    let isXLSX = fileExtension == "xlsx"
                    
                    // Only process PDF, DOCX, XLSX files
                    if isPDF || isDOCX || isXLSX {
                        let attachment = AttachmentService.shared.createAttachment(
                            type: .document,
                            data: data,
                            fileName: fileName
                        )
                        viewModel?.attachFile(attachment)
                    } else {
                        print("⚠️ Skipping unsupported file type: \(fileExtension)")
                    }
                } catch {
                    print("❌ Failed to read document \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            
            parent.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Scroll Offset Preference Key

struct ViewOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


// MARK: - Emoji Drop Delegate

struct EmojiDropDelegate: DropDelegate {
    let emoji: String
    @Binding var emojiOrder: [String]
    @Binding var draggedEmoji: String?
    
    func performDrop(info: DropInfo) -> Bool {
        draggedEmoji = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedEmoji = draggedEmoji,
              draggedEmoji != emoji,
              let fromIndex = emojiOrder.firstIndex(of: draggedEmoji),
              let toIndex = emojiOrder.firstIndex(of: emoji) else {
            return
        }
        
        withAnimation {
            emojiOrder.move(fromOffsets: IndexSet(integer: fromIndex),
                          toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }
}

// MARK: - Message Action Buttons

struct MessageActionButtons: View {
    let message: Message
    @State private var copiedAnimation = false
    @State private var sharedAnimation = false
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        if message.isFromUser {
            // USER BUTTONS - RIGHT ALIGNED (pinned to right side)
            HStack {
                Spacer()
                Button {
                    UIPasteboard.general.string = message.content
                    copiedAnimation = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedAnimation = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(copiedAnimation ? Color.green.opacity(0.3) : Color.clear)
                            .frame(width: 32, height: 32)
                        Image(systemName: copiedAnimation ? "checkmark" : "doc.on.doc")
                            .foregroundColor(copiedAnimation ? .green : .gray)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 6)
        } else {
            // RAY BUTTONS - LEFT ALIGNED (pinned to left side)
            HStack(spacing: 16) {
                // Copy button
                Button {
                    UIPasteboard.general.string = message.content
                    copiedAnimation = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedAnimation = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(copiedAnimation ? Color.green.opacity(0.3) : Color.clear)
                            .frame(width: 36, height: 36)
                        Image(systemName: copiedAnimation ? "checkmark" : "doc.on.doc")
                            .foregroundColor(copiedAnimation ? .green : .gray)
                            .font(.system(size: 18))
                    }
                }
                // Read aloud button
                Button {
                    if TextToSpeechService.shared.isSpeaking {
                        TextToSpeechService.shared.stop()
                    } else {
                        TextToSpeechService.shared.speak(message.content)
                    }
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(.gray)
                        .font(.system(size: 18))
                }
                // Share button
                Button {
                    shareMessage(message.content)
                    sharedAnimation = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        sharedAnimation = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(sharedAnimation ? Color.blue.opacity(0.3) : Color.clear)
                            .frame(width: 36, height: 36)
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(sharedAnimation ? .blue : .gray)
                            .font(.system(size: 18))
                    }
                }
                // Sources button (if any)
                if let sources = message.sources, !sources.isEmpty {
                    Button {
                        viewModel.showSourcesSheet(for: message)
                    } label: {
                        Image(systemName: "link")
                            .foregroundColor(.blue)
                            .font(.system(size: 18))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }
    
    private func shareMessage(_ text: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else { return }
        
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        rootVC.present(av, animated: true)
    }
}

// MARK: - Sources Sheet

struct SourcesSheet: View {
    let sources: [MessageSource]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List(sources) { source in
                Button {
                    if let url = URL(string: source.url) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(source.url)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(ChatViewModel())
}
