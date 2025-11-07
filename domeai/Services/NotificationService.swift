//
//  NotificationService.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//
//  NOTE: Add the following to Info.plist:
//  <key>NSUserNotificationsUsageDescription</key>
//  <string>We need permission to send you reminders and notifications.</string>
//

import Foundation
import UserNotifications
import Combine

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    
    private let center = UNUserNotificationCenter.current()
    private let storageService = StorageService.shared
    
    private override init() {
        super.init()
        center.delegate = self
        setupNotificationCategories()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                print("✅ Notification authorization granted")
            } else {
                print("❌ Notification authorization denied")
            }
            return granted
        } catch {
            print("❌ Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Notification Categories
    
    private func setupNotificationCategories() {
        // General reminder category with dismiss action
        let dismissAction = UNNotificationAction(
            identifier: NudgeAction.dismiss.rawValue,
            title: "Dismiss",
            options: []
        )
        
        let generalCategory = UNNotificationCategory(
            identifier: "GENERAL_REMINDER",
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Pill reminder category with snooze and taken actions
        let snoozeAction = UNNotificationAction(
            identifier: NudgeAction.snooze15.rawValue,
            title: "Snooze 15 min",
            options: []
        )
        
        let takenAction = UNNotificationAction(
            identifier: NudgeAction.taken.rawValue,
            title: "Taken",
            options: [.foreground]
        )
        
        let pillCategory = UNNotificationCategory(
            identifier: "PILL_REMINDER",
            actions: [snoozeAction, takenAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([generalCategory, pillCategory])
        print("✅ Notification categories registered")
    }
    
    // MARK: - Schedule Nudge
    
    func scheduleNudge(_ nudge: Nudge) {
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.body = nudge.message
        content.sound = .default
        content.categoryIdentifier = determineCategory(for: nudge)
        
        // Add user info to identify the nudge
        content.userInfo = [
            "nudgeId": nudge.id.uuidString,
            "isRecurring": nudge.isRecurring,
            "recurrenceType": nudge.recurrenceType.rawValue
        ]
        
        // Create trigger
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nudge.scheduledTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: nudge.isRecurring)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: nudge.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        center.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule nudge: \(error.localizedDescription)")
            } else {
                print("✅ Scheduled nudge: \(nudge.title) for \(nudge.scheduledTime)")
            }
        }
    }
    
    private func determineCategory(for nudge: Nudge) -> String {
        // Determine if it's a pill reminder based on keywords
        let pillKeywords = ["pill", "medication", "medicine", "dose", "take"]
        let lowerMessage = nudge.message.lowercased()
        
        if pillKeywords.contains(where: { lowerMessage.contains($0) }) {
            return "PILL_REMINDER"
        } else {
            return "GENERAL_REMINDER"
        }
    }
    
    // MARK: - Cancel Nudge
    
    func cancelNudge(id: UUID) {
        // Need to find the notification identifier for this nudge
        // For now, we'll cancel by identifier if we can find it in stored nudges
        let nudges = storageService.loadNudges()
        if let nudge = nudges.first(where: { $0.id == id }) {
            center.removePendingNotificationRequests(withIdentifiers: [nudge.notificationIdentifier])
            print("✅ Cancelled nudge: \(nudge.title)")
        }
    }
    
    func cancelNudge(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    // MARK: - Handle Actions
    
    func handleNudgeAction(action: NudgeAction, userInfo: [AnyHashable: Any]) {
        guard let nudgeIdString = userInfo["nudgeId"] as? String,
              let nudgeId = UUID(uuidString: nudgeIdString),
              let isRecurring = userInfo["isRecurring"] as? Bool else {
            print("❌ Invalid nudge user info")
            return
        }
        
        let nudges = storageService.loadNudges()
        guard let nudge = nudges.first(where: { $0.id == nudgeId }) else {
            print("❌ Nudge not found: \(nudgeIdString)")
            return
        }
        
        switch action {
        case .snooze15:
            handleSnooze(nudge: nudge)
            
        case .taken:
            handleTaken(nudge: nudge, isRecurring: isRecurring)
            
        case .dismiss:
            handleDismiss(nudge: nudge, isRecurring: isRecurring)
        }
    }
    
    private func handleSnooze(nudge: Nudge) {
        // Cancel current notification
        cancelNudge(identifier: nudge.notificationIdentifier)
        
        // Reschedule for 15 minutes later
        let snoozeDate = Date().addingTimeInterval(15 * 60)
        let snoozedNudge = Nudge(
            id: nudge.id,
            title: nudge.title,
            message: nudge.message,
            scheduledTime: snoozeDate,
            isRecurring: false, // Snoozed notifications don't recur
            recurrenceType: nudge.recurrenceType,
            notificationIdentifier: "\(nudge.notificationIdentifier)_snooze_\(UUID().uuidString.prefix(8))"
        )
        
        scheduleNudge(snoozedNudge)
        print("✅ Snoozed nudge for 15 minutes")
    }
    
    private func handleTaken(nudge: Nudge, isRecurring: Bool) {
        // Cancel current notification
        cancelNudge(identifier: nudge.notificationIdentifier)
        
        // If recurring, reschedule for next occurrence
        if isRecurring {
            let nextDate = calculateNextOccurrence(for: nudge)
            let nextNudge = Nudge(
                id: nudge.id,
                title: nudge.title,
                message: nudge.message,
                scheduledTime: nextDate,
                isRecurring: true,
                recurrenceType: nudge.recurrenceType,
                notificationIdentifier: nudge.notificationIdentifier
            )
            
            // Update in storage
            var nudges = storageService.loadNudges()
            if let index = nudges.firstIndex(where: { $0.id == nudge.id }) {
                nudges[index] = nextNudge
                storageService.saveNudges(nudges)
            }
            
            scheduleNudge(nextNudge)
            print("✅ Marked as taken, rescheduled for next occurrence")
        } else {
            // Remove from storage if not recurring
            var nudges = storageService.loadNudges()
            nudges.removeAll { $0.id == nudge.id }
            storageService.saveNudges(nudges)
            print("✅ Marked as taken, removed nudge")
        }
    }
    
    private func handleDismiss(nudge: Nudge, isRecurring: Bool) {
        // Just dismiss, don't reschedule
        cancelNudge(identifier: nudge.notificationIdentifier)
        
        // If not recurring, remove from storage
        if !isRecurring {
            var nudges = storageService.loadNudges()
            nudges.removeAll { $0.id == nudge.id }
            storageService.saveNudges(nudges)
            print("✅ Dismissed nudge")
        }
    }
    
    private func calculateNextOccurrence(for nudge: Nudge) -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch nudge.recurrenceType {
        case .daily:
            // Next occurrence at the same time tomorrow
            return calendar.date(byAdding: .day, value: 1, to: nudge.scheduledTime) ?? nudge.scheduledTime.addingTimeInterval(24 * 60 * 60)
            
        case .morningAndEvening:
            // If current time is before scheduled time, use today; otherwise tomorrow
            if now < nudge.scheduledTime {
                return nudge.scheduledTime
            } else {
                // Toggle between morning (9 AM) and evening (9 PM)
                let hour = calendar.component(.hour, from: nudge.scheduledTime)
                if hour < 12 {
                    // Currently morning, next is evening
                    var components = calendar.dateComponents([.year, .month, .day], from: now)
                    components.hour = 21 // 9 PM
                    components.minute = 0
                    return calendar.date(from: components) ?? nudge.scheduledTime.addingTimeInterval(12 * 60 * 60)
                } else {
                    // Currently evening, next is morning tomorrow
                    var components = calendar.dateComponents([.year, .month, .day], from: now)
                    components.day = (components.day ?? 0) + 1
                    components.hour = 9 // 9 AM
                    components.minute = 0
                    return calendar.date(from: components) ?? nudge.scheduledTime.addingTimeInterval(12 * 60 * 60)
                }
            }
            
        case .custom:
            // For custom, default to daily
            return calendar.date(byAdding: .day, value: 1, to: nudge.scheduledTime) ?? nudge.scheduledTime.addingTimeInterval(24 * 60 * 60)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle action button taps
        if let action = NudgeAction(rawValue: response.actionIdentifier) {
            handleNudgeAction(action: action, userInfo: userInfo)
        }
        
        completionHandler()
    }
}

