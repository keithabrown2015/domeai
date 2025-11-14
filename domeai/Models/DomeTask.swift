//
//  DomeTask.swift
//  domeai
//
//  Dome's internal task model
//

import Foundation

// DOME_TASK_MODEL_START
struct DomeTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var priority: TaskPriority
    var tags: [String]
    var reminderDate: Date?
    var notificationIdentifier: String?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        priority: TaskPriority = .medium,
        tags: [String] = [],
        reminderDate: Date? = nil,
        notificationIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.priority = priority
        self.tags = tags
        self.reminderDate = reminderDate
        self.notificationIdentifier = notificationIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum TaskPriority: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"
    
    var emoji: String {
        switch self {
        case .low: return "🟢"
        case .medium: return "🟡"
        case .high: return "🟠"
        case .urgent: return "🔴"
        }
    }
}
// DOME_TASK_MODEL_END

