//
//  Message.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let isFromUser: Bool
    let timestamp: Date
    var attachmentData: Data?  // Add this
    var attachmentType: String?  // "image" or "document"
    var sources: [MessageSource]?  // ADD THIS
    
    var isFromRay: Bool {
        !isFromUser
    }
    
    init(content: String, isFromUser: Bool, attachmentData: Data? = nil, attachmentType: String? = nil, sources: [MessageSource]? = nil) {
        self.id = UUID()  // Auto-generate
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = Date()  // Auto-set
        self.attachmentData = attachmentData
        self.attachmentType = attachmentType
        self.sources = sources
    }
}

struct MessageSource: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let url: String
    
    init(title: String, url: String) {
        self.id = UUID()
        self.title = title
        self.url = url
    }
}

