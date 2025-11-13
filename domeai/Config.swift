//
//  Config.swift
//  domeai
//

import Foundation

struct Config {
    // Vercel API Relay endpoint
    static let vercelBaseURL = "https://domeai-smoky.vercel.app"
    
    // Model hierarchy - use cheapest first
    static let defaultModel = "gpt-4o-mini"  // Fast, cheap, good for most tasks
    static let advancedModel = "gpt-4o"      // Smarter, more expensive
    static let deepThinkModel = "o1-preview" // Deep reasoning (off by default)
}
