//
//  Memory.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation

struct Memory: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let category: MemoryCategory
    let timestamp: Date
    let tags: [String]
    
    init(id: UUID = UUID(), content: String, category: MemoryCategory, timestamp: Date = Date(), tags: [String] = []) {
        self.id = id
        self.content = content
        self.category = category
        self.timestamp = timestamp
        self.tags = tags
    }
}

