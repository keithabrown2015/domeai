//
//  OpenAIService.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation
import UIKit

class OpenAIService {
    static let shared = OpenAIService()
    
    private let vercelURL = "\(Config.vercelBaseURL)/api/openai"
    private let visionURL = "\(Config.vercelBaseURL)/api/vision"
    
    private init() {}
    
    func sendChatMessage(messages: [Message], systemPrompt: String, model: String = Config.defaultModel) async throws -> String {
        print("🤖 OpenAI: Processing \(messages.count) messages via Vercel relay")
        print("🤖 Using model: \(model)")
        
        guard let url = URL(string: vercelURL) else {
            throw OpenAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        request.timeoutInterval = 30
        
        // Build FULL conversation for OpenAI
        var apiMessages: [[String: Any]] = []
        
        // Add system prompt first
        apiMessages.append([
            "role": "system",
            "content": systemPrompt
        ])
        
        // Add ALL messages from conversation history
        for msg in messages {
            apiMessages.append([
                "role": msg.isFromUser ? "user" : "assistant",
                "content": msg.content
            ])
        }
        
        print("🤖 Sending \(apiMessages.count) total messages (including system)")
        
        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.7,
            "max_tokens": 1000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🤖 Sending request to Vercel relay...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        
        print("🤖 Status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 Vercel Relay Error Response: \(errorString)")
            }
            throw OpenAIServiceError.httpError(httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIServiceError.invalidResponse
        }
        
        print("🤖 Got response: \(content)")
        return content
    }
    
    // MARK: - Image Analysis
    
    func analyzeImage(image: UIImage, prompt: String) async throws -> String {
        print("👁️ OpenAI Vision: Analyzing image via Vercel relay")
        
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Vision", code: 1, userInfo: nil)
        }
        let base64Image = imageData.base64EncodedString()
        
        guard let url = URL(string: visionURL) else {
            throw OpenAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "base64Image": base64Image,
            "prompt": prompt,
            "max_tokens": 1000
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 Vision Relay Error: \(errorString)")
            }
            throw OpenAIServiceError.invalidResponse
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIServiceError.invalidResponse
        }
        
        print("👁️ Vision analysis complete")
        return content
    }
}

// MARK: - OpenAIService Errors

enum OpenAIServiceError: LocalizedError {
    case invalidURL
    case jsonEncodingFailed
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .jsonEncodingFailed:
            return "Failed to encode request body"
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

