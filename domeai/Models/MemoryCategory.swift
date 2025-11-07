//
//  MemoryCategory.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation

enum MemoryCategory: String, CaseIterable, Codable, Hashable {
    case brain
    case notes
    case email
    case exercise
    
    var emoji: String {
        switch self {
        case .brain:
            return "🧠"
        case .notes:
            return "📝"
        case .email:
            return "📧"
        case .exercise:
            return "💪"
        }
    }
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var systemImage: String {
        switch self {
        case .brain:
            return "brain"
        case .notes:
            return "note.text"
        case .email:
            return "envelope"
        case .exercise:
            return "figure.run"
        }
    }
}

