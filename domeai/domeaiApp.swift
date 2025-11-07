//
//  domeaiApp.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI
import UserNotifications
import Speech

@main
struct domeaiApp: App {
    @StateObject private var chatViewModel = ChatViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Request permissions on app launch
        requestPermissions()
        
        // Verify API keys on app launch
        print("🔑 Config Verification:")
        print("Vercel Relay: \(Config.vercelBaseURL)")
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
                    .environmentObject(chatViewModel)
            }
            .onAppear {
                // Additional setup on first appearance
                setupNotificationDelegate()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
    }
    
    // MARK: - Permission Requests
    
    private func requestPermissions() {
        // Request speech recognition authorization
        requestSpeechRecognitionPermission()
        
        // Request notification authorization
        Task { @MainActor in
            _ = await NotificationService.shared.requestAuthorization()
        }
    }
    
    private func requestSpeechRecognitionPermission() {
        // Speech recognition permission is requested by SpeechRecognitionService
        // when it's initialized, but we can also request it explicitly here
        SFSpeechRecognizer.requestAuthorization { status in
            print("Speech recognition authorization status: \(status.rawValue)")
        }
    }
    
    // MARK: - Notification Setup
    
    private func setupNotificationDelegate() {
        // NotificationService already sets itself as delegate in its init,
        // but we ensure it's set up properly
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        print("✅ Notification delegate set up")
    }
    
    // MARK: - App Lifecycle
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            print("📱 App moved to background")
            // Save any pending data when app goes to background
            chatViewModel.saveMessagesToStorage()
            
        case .inactive:
            print("📱 App became inactive")
            
        case .active:
            print("📱 App became active")
            // Reload data when app comes to foreground
            chatViewModel.loadMessagesFromStorage()
            chatViewModel.loadMemoriesFromStorage()
            
        @unknown default:
            break
        }
    }
}
