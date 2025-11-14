//
//  MemoryCategory.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation

enum MemoryCategory: String, CaseIterable, Codable, Hashable {
    // DOME_MEMORY_CATEGORIES_START
    case brain       // General knowledge Ray learns
    case notes       // User's notes
    case email       // Email-related info
    case exercise    // Fitness & health
    case work        // Work-related items
    case personal    // Personal life
    case recipes     // Food & cooking
    case shopping    // Shopping lists & purchases
    case doctor      // Medical & appointments
    case finance     // Money & budgeting
    case judge       // Legal matters (custom example)
    case ideas       // Creative ideas
    case links       // Saved URLs
    case lists       // General lists
    case important   // High-priority items
    case events      // Event memories (different from calendar)
    case tasks       // Task memories (different from active tasks)
    // DOME_MEMORY_CATEGORIES_END
    
    var emoji: String {
        switch self {
        case .brain: return "🧠"
        case .notes: return "📝"
        case .email: return "📧"
        case .exercise: return "💪"
        case .work: return "💼"
        case .personal: return "👤"
        case .recipes: return "🍳"
        case .shopping: return "🛒"
        case .doctor: return "🏥"
        case .finance: return "💰"
        case .judge: return "⚖️"
        case .ideas: return "💡"
        case .links: return "🔗"
        case .lists: return "📋"
        case .important: return "⭐"
        case .events: return "🎉"
        case .tasks: return "✅"
        }
    }
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var systemImage: String {
        switch self {
        case .brain: return "brain"
        case .notes: return "note.text"
        case .email: return "envelope"
        case .exercise: return "figure.run"
        case .work: return "briefcase"
        case .personal: return "person"
        case .recipes: return "fork.knife"
        case .shopping: return "cart"
        case .doctor: return "cross.case"
        case .finance: return "dollarsign.circle"
        case .judge: return "scale.3d"
        case .ideas: return "lightbulb"
        case .links: return "link"
        case .lists: return "list.bullet"
        case .important: return "star.fill"
        case .events: return "calendar.badge.exclamationmark"
        case .tasks: return "checkmark.circle"
        }
    }
}

