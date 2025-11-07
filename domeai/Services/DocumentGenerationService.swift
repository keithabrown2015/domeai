//
//  DocumentGenerationService.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation
import UIKit
import PDFKit
import UniformTypeIdentifiers

class DocumentGenerationService {
    static let shared = DocumentGenerationService()
    
    // Generate PDF from text
    func generatePDF(content: String, title: String) -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: "Dome-AI",
            kCGPDFContextAuthor: "Ray",
            kCGPDFContextTitle: title
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0  // US Letter
        let pageHeight = 11 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let fileName = "\(title.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).pdf"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pdfURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try renderer.writePDF(to: pdfURL) { (context) in
                context.beginPage()
                
                let titleFont = UIFont.boldSystemFont(ofSize: 18)
                let bodyFont = UIFont.systemFont(ofSize: 12)
                
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: titleFont
                ]
                
                let bodyAttributes: [NSAttributedString.Key: Any] = [
                    .font: bodyFont
                ]
                
                // Title
                let titleRect = CGRect(x: 50, y: 50, width: pageWidth - 100, height: 50)
                title.draw(in: titleRect, withAttributes: titleAttributes)
                
                // Body content
                let bodyRect = CGRect(x: 50, y: 120, width: pageWidth - 100, height: pageHeight - 170)
                content.draw(in: bodyRect, withAttributes: bodyAttributes)
            }
            
            print("📄 PDF generated at: \(pdfURL.path)")
            return pdfURL
            
        } catch {
            print("🔴 PDF generation error: \(error)")
            return nil
        }
    }
    
    // Generate simple DOCX (text-based)
    func generateDOCX(content: String, title: String) -> URL? {
        // Create basic .txt file (we can't create true .docx without external libraries)
        // But we can create RTF which is compatible
        let fileName = "\(title.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).rtf"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let docURL = documentsPath.appendingPathComponent(fileName)
        
        // Create RTF content
        let rtfContent = """
        {\\rtf1\\ansi\\deff0
        {\\fonttbl{\\f0 Helvetica;}}
        {\\b\\f0\\fs28 \(title)\\par}
        \\par
        \\f0\\fs24 \(content.replacingOccurrences(of: "\n", with: "\\par\n"))
        }
        """
        
        do {
            try rtfContent.write(to: docURL, atomically: true, encoding: .utf8)
            print("📝 Document generated at: \(docURL.path)")
            return docURL
        } catch {
            print("🔴 Document generation error: \(error)")
            return nil
        }
    }
    
    // Generate CSV (which Excel can open)
    func generateSpreadsheet(data: [[String]], title: String, headers: [String]) -> URL? {
        let fileName = "\(title.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).csv"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let csvURL = documentsPath.appendingPathComponent(fileName)
        
        var csvString = headers.joined(separator: ",") + "\n"
        
        for row in data {
            let rowString = row.map { "\"\($0)\"" }.joined(separator: ",")
            csvString += rowString + "\n"
        }
        
        do {
            try csvString.write(to: csvURL, atomically: true, encoding: .utf8)
            print("📊 Spreadsheet generated at: \(csvURL.path)")
            return csvURL
        } catch {
            print("🔴 Spreadsheet generation error: \(error)")
            return nil
        }
    }
    
    // Share file
    func shareFile(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else { return }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
}

