//
//  Nudge.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation

enum RecurrenceType: String, Codable {
    case daily
    case morningAndEvening
    case custom
}

struct Nudge: Identifiable, Codable {
    let id: UUID
    let title: String
    let message: String
    let scheduledTime: Date
    let isRecurring: Bool
    let recurrenceType: RecurrenceType
    let notificationIdentifier: String
    
    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        scheduledTime: Date,
        isRecurring: Bool = false,
        recurrenceType: RecurrenceType = .daily,
        notificationIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.scheduledTime = scheduledTime
        self.isRecurring = isRecurring
        self.recurrenceType = recurrenceType
        self.notificationIdentifier = notificationIdentifier ?? "nudge_\(id.uuidString)"
    }
}

enum NudgeAction: String {
    case snooze15 = "SNOOZE_15"
    case taken = "TAKEN"
    case dismiss = "DISMISS"
}

