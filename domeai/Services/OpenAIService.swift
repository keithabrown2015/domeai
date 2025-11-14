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
    
    private let chatRelayURL = "\(Config.vercelBaseURL)/api/openai"
    private let visionURL = "\(Config.vercelBaseURL)/api/vision"
    
    private init() {}
    
    func sendChatMessage(messages: [Message], systemPrompt: String, model: String = "gpt-4o-mini") async throws -> String {
        // RAY_OPENAI_CONTEXT_UPGRADE_START
        print("🤖 OpenAI: Processing \(messages.count) messages via relay")
        
        guard let url = URL(string: chatRelayURL) else {
            throw OpenAIServiceError.invalidURL
        }
        
        print("RAY_RELAY_URL = \(url.absoluteString)")
        print("🤖 Request URL: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        request.timeoutInterval = 30
        
        var chatMessages: [ChatCompletionMessageRequest] = [
            ChatCompletionMessageRequest(role: "system", content: systemPrompt)
        ]
        
        let relevantMessages = messages.suffix(10)
        relevantMessages.forEach { message in
            let role = message.isFromUser ? "user" : "assistant"
            chatMessages.append(ChatCompletionMessageRequest(role: role, content: message.content))
        }
        
        let requestPayload = ChatCompletionRequest(
            model: model,
            messages: chatMessages,
            maxTokens: 1000,
            temperature: 0.7
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestPayload)
        
        if let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            print("RAY_REQUEST_BODY =", bodyString)
        }
        
        print("🤖 Sending request to relay...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        
        print("🤖 Status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "No error details"
            print("🔴 Vercel Relay Error - Status: \(httpResponse.statusCode)")
            print("🔴 Error Response: \(errorString)")
            print("🔴 Request URL: \(chatRelayURL)")
            throw OpenAIServiceError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        if let errorPayload = try? decoder.decode(OpenAIErrorPayload.self, from: data) {
            let errorMessage = errorPayload.error.message
            print("🔴 OpenAI Error:", errorMessage)
            throw OpenAIServiceError.apiError(errorMessage)
        }
        
        let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
        
        guard let content = completionResponse.choices.first?.message.content else {
            print("⚠️ Relay response did not contain expected fields")
            throw OpenAIServiceError.invalidResponse
        }
        
        print("🤖 Relay response: \(content.prefix(100))...")
        return content
        // RAY_OPENAI_CONTEXT_UPGRADE_END
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
        
        print("DomeAI request URL: \(url.absoluteString)")
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
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "No error details"
            print("🔴 Vision Relay Error - Status: \(httpResponse.statusCode)")
            print("🔴 Error Response: \(errorString)")
            print("🔴 Request URL: \(visionURL)")
            throw OpenAIServiceError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        if let errorPayload = try? decoder.decode(OpenAIErrorPayload.self, from: data) {
            let errorMessage = errorPayload.error.message
            print("🔴 Vision Relay Error:", errorMessage)
            throw OpenAIServiceError.apiError(errorMessage)
        }
        
        let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
        
        guard let content = completionResponse.choices.first?.message.content else {
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

// MARK: - OpenAI Models

struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatCompletionChoice]
    let usage: ChatCompletionUsage?
    let systemFingerprint: String?
}

struct ChatCompletionChoice: Codable {
    let index: Int
    let message: ChatCompletionMessageResponse
    let finishReason: String?
    let logprobs: ChatCompletionLogprobs?
}

struct ChatCompletionMessageResponse: Codable {
    let role: String
    let content: String
    let refusal: String?
    let toolCalls: [ChatCompletionToolCall]?
}

struct ChatCompletionToolCall: Codable {
    let id: String
    let type: String
    let function: ChatCompletionToolFunction?
}

struct ChatCompletionToolFunction: Codable {
    let name: String
    let arguments: String
}

struct ChatCompletionLogprobs: Codable {
    let content: [ChatCompletionLogprobToken]?
}

struct ChatCompletionLogprobToken: Codable {
    let token: String?
    let logprob: Double?
    let bytes: [Int]?
}

struct ChatCompletionUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}

struct OpenAIErrorPayload: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String?
    let param: String?
    let code: String?
}

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatCompletionMessageRequest]
    let maxTokens: Int?
    let temperature: Double?
}

struct ChatCompletionMessageRequest: Encodable {
    let role: String
    let content: String
}

