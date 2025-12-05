//
//  GoogleSearchService.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation

// MARK: - SearchResult

struct SearchResult: Identifiable, Codable {
    let id: UUID
    let title: String
    let snippet: String
    let link: String
    
    init(id: UUID = UUID(), title: String, snippet: String, link: String) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.link = link
    }
    
    // Custom CodingKeys to match Google API response
    enum CodingKeys: String, CodingKey {
        case title
        case snippet
        case link
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.snippet = try container.decode(String.self, forKey: .snippet)
        self.link = try container.decode(String.self, forKey: .link)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(snippet, forKey: .snippet)
        try container.encode(link, forKey: .link)
    }
}

// MARK: - GoogleSearchService

class GoogleSearchService {
    static let shared = GoogleSearchService()
    
    private let searchURL = "\(Config.vercelBaseURL)/api/google-search"
    
    private init() {}
    
    // MARK: - Search with Ray Response
    
    func searchWithResponse(query: String) async throws -> (message: String, sources: [String], searchPerformed: Bool) {
        print("🔍🔍🔍 GoogleSearchService.searchWithResponse() via Vercel relay 🔍🔍🔍")
        print("🔍 Query: '\(query)'")
        
        guard let url = URL(string: searchURL) else {
            print("🔴 Failed to build URL")
            throw GoogleSearchServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        
        let body: [String: Any] = [
            "query": query,
            "num": "10"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("DomeAI request URL: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("🔴 Invalid response type")
            throw GoogleSearchServiceError.invalidResponse
        }
        
        print("🔍 HTTP Status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "No error details"
            print("🔴 Search Relay Error - Status: \(httpResponse.statusCode)")
            print("🔴 Error Response: \(errorString)")
            print("🔴 Request URL: \(url.absoluteString)")
            throw GoogleSearchServiceError.httpError(httpResponse.statusCode)
        }
        
        // Parse new response format
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let json = json else {
            print("🔴 JSON is nil")
            throw GoogleSearchServiceError.invalidResponse
        }
        
        print("🔍 JSON keys: \(Array(json.keys))")
        
        // Check for new response format
        guard let ok = json["ok"] as? Bool, ok else {
            print("🔴 Response indicates error or invalid format")
            throw GoogleSearchServiceError.invalidResponse
        }
        
        // Extract Ray's message (prefer "reply" over "message")
        let message = (json["reply"] as? String) ?? (json["message"] as? String) ?? ""
        let sources = (json["sources"] as? [String]) ?? []
        let searchPerformed = (json["searchPerformed"] as? Bool) ?? false
        
        if message.isEmpty {
            print("🔴 No message or reply in response")
            throw GoogleSearchServiceError.invalidResponse
        }
        
        print("✅ Ray's response extracted (\(message.count) characters)")
        print("🔍 Search performed: \(searchPerformed), Sources: \(sources.count)")
        
        return (message: message, sources: sources, searchPerformed: searchPerformed)
    }
    
    func search(query: String) async throws -> [SearchResult] {
        print("🔍🔍🔍 GoogleSearchService.search() via Vercel relay 🔍🔍🔍")
        print("🔍 Query: '\(query)'")
        
        guard let url = URL(string: searchURL) else {
            print("🔴 Failed to build URL")
            throw GoogleSearchServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ConfigSecret.appToken, forHTTPHeaderField: "X-App-Token")
        
        let body: [String: Any] = [
            "query": query,
            "num": "10"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("DomeAI request URL: \(url.absoluteString)")
        
        // Make the request - SAME LOGIC AS BEFORE
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("🔴 Invalid response type")
            throw GoogleSearchServiceError.invalidResponse
        }
        
        print("🔍 HTTP Status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "No error details"
            print("🔴 Search Relay Error - Status: \(httpResponse.statusCode)")
            print("🔴 Error Response: \(errorString)")
            print("🔴 Request URL: \(url.absoluteString)")
            throw GoogleSearchServiceError.httpError(httpResponse.statusCode)
        }
        
        // Parse new response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("🔍 JSON is nil")
            throw GoogleSearchServiceError.invalidResponse
        }
        
        print("🔍 JSON keys: \(Array(json.keys))")
        
        // Check for new response format
        guard let ok = json["ok"] as? Bool, ok else {
            print("🔴 Response indicates error or invalid format")
            throw GoogleSearchServiceError.invalidResponse
        }
        
        // Extract sources from the new format
        var results: [SearchResult] = []
        if let sources = json["sources"] as? [String] {
            print("🔍 Found \(sources.count) sources")
            results = sources.compactMap { url -> SearchResult? in
                // Extract domain name for title
                let title = URL(string: url)?.host ?? "Source"
                return SearchResult(
                    title: title,
                    snippet: url,
                    link: url
                )
            }
        } else {
            // Fallback: try old format with "items" array
            if let items = json["items"] as? [[String: Any]] {
                print("🔍 Found \(items.count) items (legacy format)")
                results = items.compactMap { item -> SearchResult? in
                    guard let title = item["title"] as? String,
                          let snippet = item["snippet"] as? String,
                          let link = item["link"] as? String else {
                        return nil
                    }
                    return SearchResult(title: title, snippet: snippet, link: link)
                }
            } else {
                print("⚠️ No sources or items found in response")
            }
        }
        
        print("🔍 Returning \(results.count) results")
        return results
    }
    
    // MARK: - Full Content Fetching (Optional Enhancement)
    
    func fetchFullContent(url: String) async throws -> String {
        guard let pageURL = URL(string: url) else {
            throw NSError(domain: "Fetch", code: 1, userInfo: nil)
        }
        
        let (data, _) = try await URLSession.shared.data(from: pageURL)
        
        // Extract text from HTML (basic implementation)
        if let html = String(data: data, encoding: .utf8) {
            // Strip HTML tags for basic text extraction
            let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            return String(stripped.prefix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return ""
    }
}

// MARK: - GoogleSearchService Errors

enum GoogleSearchServiceError: LocalizedError {
    case missingAPIKey
    case missingSearchEngineID
    case invalidQuery
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Search API key is missing. Please check your configuration."
        case .missingSearchEngineID:
            return "Search configuration is missing. Please check your configuration."
        case .invalidQuery:
            return "Invalid search query"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from search API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Search API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

