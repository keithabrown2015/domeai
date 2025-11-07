//
//  Attachment.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation
import UIKit

enum AttachmentType: String, Codable {
    case photo
    case document
}

struct Attachment: Identifiable {
    let id: UUID
    let type: AttachmentType
    let data: Data
    let fileName: String
    var thumbnail: UIImage?
    
    init(id: UUID = UUID(), type: AttachmentType, data: Data, fileName: String, thumbnail: UIImage? = nil) {
        self.id = id
        self.type = type
        self.data = data
        self.fileName = fileName
        self.thumbnail = thumbnail
    }
}

