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
    
    private let rayRelayURL = "\(Config.vercelBaseURL)/api/ray"
    private let visionURL = "\(Config.vercelBaseURL)/api/vision"
    
    private init() {}
    
    /// NEW SIMPLE FUNCTION: Send chat message with explicit conversationHistory
    /// This function receives the conversationHistory already built, ensuring it's correct
    func sendChatMessageWithHistory(messages: [Message], conversationHistory: [[String: String]], systemPrompt: String, model: String = "gpt-4o-mini") async throws -> String {
        print("\n" + String(repeating: "=", count: 80))
        print("📤 sendChatMessageWithHistory CALLED")
        print("📤 Received messages.count: \(messages.count)")
        print("📤 Received conversationHistory.count: \(conversationHistory.count)")
        
        // CRITICAL VERIFICATION: conversationHistory should match messages count
        if conversationHistory.count != messages.count {
            print("❌ ERROR: conversationHistory count (\(conversationHistory.count)) != messages count (\(messages.count))")
        }
        
        guard let url = URL(string: rayRelayURL) else {
            throw OpenAIServiceError.invalidURL
        }
        
        // Extract user query (last user message)
        let userMessages = messages.filter { $0.isFromUser }
        guard let userQuery = userMessages.last?.content else {
            throw OpenAIServiceError.invalidQuery
        }
        
        // Build request body with the conversationHistory we received
        let requestBody: [String: Any] = [
            "query": userQuery,
            "conversationHistory": conversationHistory
        ]
        
        // CRITICAL DEBUG: Log exactly what we're sending
        print("📤 REQUEST BODY:")
        print("📤   query: \"\(userQuery.prefix(60))\"")
        print("📤   conversationHistory.count: \(conversationHistory.count)")
        print("📤   conversationHistory:")
        for (index, msg) in conversationHistory.enumerated() {
            let role = msg["role"] ?? "?"
            let content = msg["content"] ?? ""
            print("📤     [\(index + 1)] \(role.uppercased()): \"\(content.prefix(60))\"")
        }
        print(String(repeating: "=", count: 80) + "\n")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "No error details"
            throw OpenAIServiceError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let message = json["message"] as? String else {
            throw OpenAIServiceError.invalidResponse
        }
        
        return message
    }
    
    /// OLD FUNCTION: Keep for backward compatibility but mark as deprecated
    func sendChatMessage(messages: [Message], systemPrompt: String, model: String = "gpt-4o-mini") async throws -> String {
        print("🎯 Ray: Processing message via smart routing")
        
        // CRITICAL VERIFICATION: Log what we actually received
        print("\n" + String(repeating: "=", count: 80))
        print("📥 OpenAIService.sendChatMessage RECEIVED:")
        print("📥 messages parameter count: \(messages.count)")
        print("📥 Full messages array received:")
        for (index, msg) in messages.enumerated() {
            let role = msg.isFromUser ? "USER" : "ASSISTANT"
            let preview = msg.content.count > 60 ? String(msg.content.prefix(60)) + "..." : msg.content
            print("📥   [\(index + 1)] \(role): \"\(preview)\"")
        }
        print(String(repeating: "=", count: 80) + "\n")
        
        guard let url = URL(string: rayRelayURL) else {
            throw OpenAIServiceError.invalidURL
        }
        
        print("RAY_RELAY_URL = \(url.absoluteString)")
        print("🎯 Request URL: \(url.absoluteString)")
        
        // Extract the user's query from messages (use last user message)
        let userMessages = messages.filter { $0.isFromUser }
        let userQuery: String
        if let lastUserMessage = userMessages.last {
            userQuery = lastUserMessage.content
        } else if let firstMessage = messages.first {
            userQuery = firstMessage.content
        } else {
            throw OpenAIServiceError.invalidQuery
        }
        
        // RAY'S CONVERSATION MEMORY:
        // Build conversation history from the messages array (same array used to display messages in UI)
        // This ensures Ray sees the full conversation context, not just the current message
        // Format: OpenAI chat format with "role" (user/assistant) and "content" (message text)
        
        // CRITICAL VERIFICATION: If messages array only has 1 message, something is wrong
        if messages.count == 1 {
            print("❌ CRITICAL ERROR: sendChatMessage received only 1 message!")
            print("❌ This means conversation history was lost before reaching this function!")
            print("❌ The messages array passed to this function should contain ALL previous messages!")
        }
        
        // CRITICAL: Limit history size to avoid memory issues
        // If we have more than 20 messages, trim the oldest ones but keep recent exchanges
        let maxHistoryMessages = 20
        let messagesToInclude: [Message]
        if messages.count > maxHistoryMessages {
            // Keep the most recent messages (preserves recent conversation turns)
            // Always keep at least the last 10 messages for continuity
            let messagesToKeep = max(10, maxHistoryMessages)
            messagesToInclude = Array(messages.suffix(messagesToKeep))
            print("📤 Trimming conversation history: \(messages.count) -> \(messagesToInclude.count) messages")
        } else {
            // Include all messages if we're under the limit
            messagesToInclude = messages
            print("📤 Including ALL \(messages.count) messages (no trimming needed)")
        }
        
        // CRITICAL: Ensure we're sending ALL messages in the trimmed array
        // Map each message to the format expected by the backend
        let conversationHistory: [[String: String]] = messagesToInclude.map { message in
            [
                "role": message.isFromUser ? "user" : "assistant",
                "content": message.content
            ]
        }
        
        // CRITICAL DEBUG LOGGING: Log the full conversation history being sent
        // This log MUST match what the backend receives
        print("\n" + String(repeating: "=", count: 80))
        print("📤 iOS SENDING conversationHistory WITH \(conversationHistory.count) MESSAGES:")
        print("📤 Input messages array had: \(messages.count) messages")
        print("📤 After trimming (if needed): \(messagesToInclude.count) messages")
        print(String(repeating: "-", count: 80))
        for (index, msg) in conversationHistory.enumerated() {
            let role = msg["role"] ?? "?"
            let content = msg["content"] ?? ""
            let preview = content.count > 80 ? String(content.prefix(80)) : content
            print("📤   [\(index + 1)] \(role.uppercased()): \"\(preview)\"")
        }
        print(String(repeating: "=", count: 80) + "\n")
        
        // VERIFICATION: Ensure conversationHistory has at least the expected number of messages
        // For a conversation with N user messages, we should have at least N messages (user + assistant pairs)
        let userMessageCount = messagesToInclude.filter { $0.isFromUser }.count
        let assistantMessageCount = messagesToInclude.filter { !$0.isFromUser }.count
        print("📤 VERIFICATION: User messages: \(userMessageCount), Assistant messages: \(assistantMessageCount), Total: \(conversationHistory.count)")
        
        if conversationHistory.count == 0 {
            print("❌ ERROR: conversationHistory is EMPTY! This should never happen.")
        } else if conversationHistory.count == 1 && conversationHistory.first?["role"] == "user" {
            print("⚠️ WARNING: Only 1 user message in conversationHistory.")
            print("⚠️ This should only happen on the FIRST message of a conversation.")
            print("⚠️ If this is NOT the first message, conversation history was lost!")
        } else if conversationHistory.count >= 2 {
            print("✅ GOOD: Multiple messages in conversationHistory - conversation context is being maintained")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        request.timeoutInterval = 30
        
        // /api/ray endpoint expects: { "query": "current message", "conversationHistory": [...] }
        let requestBody: [String: Any] = [
            "query": userQuery,
            "conversationHistory": conversationHistory
        ]
        
        // CRITICAL VERIFICATION: Ensure conversationHistory contains all expected messages
        // For second message, we should have: [user1, assistant1, user2]
        print("📤 FINAL VERIFICATION BEFORE SENDING:")
        print("📤 conversationHistory count: \(conversationHistory.count)")
        print("📤 Expected for second message: 3 messages [user, assistant, user]")
        if conversationHistory.count == 3 {
            let msg1Role = conversationHistory[0]["role"] ?? "unknown"
            let msg2Role = conversationHistory[1]["role"] ?? "unknown"
            let msg3Role = conversationHistory[2]["role"] ?? "unknown"
            if msg1Role == "user" && msg2Role == "assistant" && msg3Role == "user" {
                print("✅ PERFECT: conversationHistory has correct pattern [user, assistant, user]")
            } else {
                print("⚠️ WARNING: conversationHistory pattern is [\(msg1Role), \(msg2Role), \(msg3Role)]")
            }
        }
        
        // CRITICAL: iOS-side debug log RIGHT BEFORE making the network call
        // This MUST match what the backend receives
        print("\n" + String(repeating: "=", count: 80))
        print("📤 iOS SENDING conversationHistory WITH \(conversationHistory.count) MESSAGES:")
        for (index, msg) in conversationHistory.enumerated() {
            let role = msg["role"] as? String ?? "?"
            let content = msg["content"] as? String ?? ""
            print("📤   [\(index + 1)] \(role.uppercased()): \"\(content.prefix(80))\"")
        }
        print(String(repeating: "=", count: 80) + "\n")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Log the actual JSON being sent (for debugging)
        if let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            print("📤 RAY_REQUEST_BODY JSON (first 500 chars):")
            let preview = bodyString.count > 500 ? String(bodyString.prefix(500)) + "..." : bodyString
            print(preview)
        }
        
        print("🎯 Sending request to Ray relay...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        
        print("🎯 Status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "No error details"
            print("🔴 Ray Relay Error - Status: \(httpResponse.statusCode)")
            print("🔴 Error Response: \(errorString)")
            print("🔴 Request URL: \(rayRelayURL)")
            throw OpenAIServiceError.httpError(httpResponse.statusCode)
        }
        
        // Parse new response format: { "ok": true, "tier": 1|2|3, "model": "...", "message": "...", "reasoning": "...", "sources": [...] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("🔴 Invalid JSON response")
            throw OpenAIServiceError.invalidResponse
        }
        
        guard let ok = json["ok"] as? Bool, ok else {
            if let errorMessage = json["error"] as? String {
                print("🔴 Ray Error:", errorMessage)
                throw OpenAIServiceError.apiError(errorMessage)
            }
            throw OpenAIServiceError.invalidResponse
        }
        
        // Extract message from response
        guard let message = json["message"] as? String else {
            print("⚠️ Ray response did not contain message field")
            throw OpenAIServiceError.invalidResponse
        }
        
        // Log tier and model info
        if let tier = json["tier"] as? Int,
           let model = json["model"] as? String,
           let reasoning = json["reasoning"] as? String {
            print("🎯 Tier: \(tier), Model: \(model), Reasoning: \(reasoning)")
        }
        
        // Log sources if present
        if let sources = json["sources"] as? [String], !sources.isEmpty {
            print("🔍 Sources: \(sources.count) found")
        }
        
        print("✅ Ray response: \(message.prefix(100))...")
        return message
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
    
    // MARK: - Email Test
    
    func sendTestEmail(to email: String?) async throws {
        let emailURL = "\(Config.vercelBaseURL)/api/ray/send-email"
        
        guard let url = URL(string: emailURL) else {
            throw OpenAIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "to": email as Any,
            "subject": "Test email from Ray",
            "html": "<p>This is a test email sent from Ray through DomeAI.</p>"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("📧 Sending test email to: \(email ?? "default")")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }
        
        print("📧 Email API response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorString = String(data: data, encoding: .utf8) ?? "No error details"
            print("📧 Email API error response: \(errorString)")
            throw OpenAIServiceError.httpError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIServiceError.invalidResponse
        }
        
        print("📧 Email API response: \(json)")
        
        guard let ok = json["ok"] as? Bool, ok else {
            if let errorMessage = json["error"] as? String {
                throw OpenAIServiceError.apiError(errorMessage)
            }
            throw OpenAIServiceError.invalidResponse
        }
        
        print("✅ Test email sent successfully")
    }
}

// MARK: - OpenAIService Errors

enum OpenAIServiceError: LocalizedError {
    case invalidURL
    case invalidQuery
    case jsonEncodingFailed
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidQuery:
            return "Invalid query - no user message found"
        case .jsonEncodingFailed:
            return "Failed to encode request body"
        case .invalidResponse:
            return "Invalid response from Ray API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Ray API error: \(message)"
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


