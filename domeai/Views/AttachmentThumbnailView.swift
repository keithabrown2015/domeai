//
//  AttachmentThumbnailView.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI
import UIKit

struct AttachmentThumbnailView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    
    var body: some View {
        if let attachment = viewModel.currentAttachment {
            HStack(spacing: 12) {
                // Thumbnail
                if let thumbnail = attachment.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: attachment.type == .photo ? "photo" : "doc.fill")
                                .foregroundColor(.gray)
                        )
                }
                
                // File name
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(attachment.type == .photo ? "Photo" : "Document")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Remove button
                Button {
                    viewModel.removeAttachment()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject var viewModel = ChatViewModel()
        
        var body: some View {
            VStack {
                AttachmentThumbnailView()
                Spacer()
            }
            .environmentObject(viewModel)
            .onAppear {
                let testImage = UIImage(systemName: "photo")!
                let imageData = testImage.pngData()!
                let attachment = AttachmentService.shared.createAttachment(
                    type: .photo,
                    data: imageData,
                    fileName: "test_photo.jpg"
                )
                viewModel.attachFile(attachment)
            }
        }
    }
    
    return PreviewWrapper()
}

