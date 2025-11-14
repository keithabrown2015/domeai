//
//  DomeEvent.swift
//  domeai
//
//  Dome's internal calendar event model
//

import Foundation

// DOME_CALENDAR_MODEL_START
struct DomeEvent: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var notes: String?
    var startDate: Date
    var endDate: Date?
    var isAllDay: Bool
    var tags: [String]
    var reminderMinutesBefore: Int? // e.g., 15 for 15 minutes before
    var notificationIdentifier: String?
    var recurrence: EventRecurrence?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        tags: [String] = [],
        reminderMinutesBefore: Int? = nil,
        notificationIdentifier: String? = nil,
        recurrence: EventRecurrence? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.tags = tags
        self.reminderMinutesBefore = reminderMinutesBefore
        self.notificationIdentifier = notificationIdentifier
        self.recurrence = recurrence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum EventRecurrence: String, Codable {
    case daily
    case weekly
    case monthly
    case yearly
}
// DOME_CALENDAR_MODEL_END

