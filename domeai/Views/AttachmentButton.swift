//
//  AttachmentButton.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

struct AttachmentButton: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var showingActionSheet = false
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImage: UIImage?
    
    var body: some View {
        Button {
            showingActionSheet = true
        } label: {
            Text("📎")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
        }
        .confirmationDialog("Add Attachment", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("Camera") {
                requestCameraPermission()
            }
            Button("Photo Library") {
                imagePickerSourceType = .photoLibrary
                showingImagePicker = true
            }
            Button("Documents") {
                showingDocumentPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                sourceType: imagePickerSourceType,
                selectedImage: $selectedImage
            )
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker()
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                handleImageSelection(image)
            }
        }
    }
    
    private func requestCameraPermission() {
        // Check camera authorization status
        // Note: Add NSCameraUsageDescription to Info.plist
        // <key>NSCameraUsageDescription</key>
        // <string>We need access to your camera to attach photos to messages.</string>
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            imagePickerSourceType = .camera
            showingImagePicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        imagePickerSourceType = .camera
                        showingImagePicker = true
                    }
                }
            }
        default:
            print("⚠️ Camera access denied")
            // Could show an alert here to inform user
        }
    }
    
    private func handleImageSelection(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert image to data")
            return
        }
        
        let fileName = "photo_\(UUID().uuidString.prefix(8)).jpg"
        let attachment = AttachmentService.shared.createAttachment(
            type: .photo,
            data: imageData,
            fileName: fileName
        )
        viewModel.attachFile(attachment)
        selectedImage = nil // Reset for next selection
    }
}

// MARK: - ImagePicker

struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - DocumentPicker

struct DocumentPicker: UIViewControllerRepresentable {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Note: Add UISupportsDocumentBrowser key to Info.plist if needed
        // For document access, may need NSPhotoLibraryUsageDescription if accessing photos
        // <key>NSPhotoLibraryUsageDescription</key>
        // <string>We need access to your photo library to attach photos to messages.</string>
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, viewModel: viewModel)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        weak var viewModel: ChatViewModel?
        
        init(_ parent: DocumentPicker, viewModel: ChatViewModel) {
            self.parent = parent
            self.viewModel = viewModel
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Access security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Failed to access security-scoped resource")
                parent.dismiss()
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                
                let attachment = AttachmentService.shared.createAttachment(
                    type: .document,
                    data: data,
                    fileName: fileName
                )
                viewModel?.attachFile(attachment)
            } catch {
                print("❌ Failed to read document: \(error.localizedDescription)")
            }
            
            parent.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

