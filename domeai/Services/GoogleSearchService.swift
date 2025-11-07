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
        
        print("🔍 Request URL: \(url.absoluteString)")
        
        // Make the request - SAME LOGIC AS BEFORE
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("🔴 Invalid response type")
            throw GoogleSearchServiceError.invalidResponse
        }
        
        print("🔍 HTTP Status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 Search Relay Error: \(errorString)")
            }
            throw GoogleSearchServiceError.httpError(httpResponse.statusCode)
        }
        
        // Parse response - EXACT SAME AS BEFORE
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let json = json {
            print("🔍 JSON keys: \(Array(json.keys))")
        } else {
            print("🔍 JSON is nil")
        }
        
        guard let items = json?["items"] as? [[String: Any]] else {
            print("🔴 No 'items' in response")
            return []
        }
        
        print("🔍 Found \(items.count) items")
        
        let results = items.compactMap { item -> SearchResult? in
            guard let title = item["title"] as? String,
                  let snippet = item["snippet"] as? String,
                  let link = item["link"] as? String else {
                return nil
            }
            return SearchResult(title: title, snippet: snippet, link: link)
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
            return "Google Search API key is missing. Please add your API key to Config.swift"
        case .missingSearchEngineID:
            return "Google Custom Search Engine ID (CX) is missing. Please add it to Config.swift"
        case .invalidQuery:
            return "Invalid search query"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Google Search API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Google Search API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

