//
//  AttachmentService.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation
import UIKit
import Combine

class AttachmentService: NSObject, ObservableObject {
    static let shared = AttachmentService()
    
    @Published var currentAttachment: Attachment?
    
    let maxAttachments = 1
    
    private override init() {
        super.init()
    }
    
    func generateThumbnail(for attachment: Attachment) -> UIImage? {
        switch attachment.type {
        case .photo:
            // For photos, the data is the image itself
            return UIImage(data: attachment.data)
            
        case .document:
            // For documents, generate a generic document icon
            let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
            return UIImage(systemName: "doc.fill", withConfiguration: config)?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        }
    }
    
    func createAttachment(type: AttachmentType, data: Data, fileName: String) -> Attachment {
        var attachment = Attachment(
            type: type,
            data: data,
            fileName: fileName
        )
        attachment.thumbnail = generateThumbnail(for: attachment)
        return attachment
    }
}

