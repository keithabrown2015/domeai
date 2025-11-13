//
//  ChatViewModel.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation
import SwiftUI
import UIKit
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var messages: [Message] = []
    @Published var memories: [Memory] = []
    @Published var nudges: [Nudge] = []
    @Published var currentAttachment: Attachment? = nil
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var recognizedText: String = ""
    @Published var showingSourcesSheet = false
    @Published var selectedMessageSources: [MessageSource] = []
    @Published var isRefreshing: Bool = false
    
    // MARK: - Services
    
    private let storageService = StorageService.shared
    private let speechService = SpeechRecognitionService()
    private let ttsService = TextToSpeechService.shared
    private let attachmentService = AttachmentService.shared
    private let notificationService = NotificationService.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        loadMessages()
        loadMemories()
        loadNudges()
        
        // Observe recognized text from speech service
        speechService.$recognizedText
            .receive(on: DispatchQueue.main)
            .assign(to: \.recognizedText, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Loading Data
    
    private func loadMessages() {
        messages = storageService.loadMessages()
    }
    
    private func loadMemories() {
        memories = storageService.loadMemories()
    }
    
    private func loadNudges() {
        nudges = storageService.loadNudges()
    }
    
    // MARK: - Message Handling
    
    func sendMessage(content: String) {
        print("🟢 ChatViewModel.sendMessage called with: '\(content)'")
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentAttachment != nil else {
            print("🟢 sendMessage: Empty content, returning")
            return
        }
        
        var messageContent = content
        var attachmentData: Data? = nil
        var attachmentType: String? = nil
        
        if let attachment = currentAttachment {
            attachmentData = attachment.data
            attachmentType = attachment.type == .photo ? "image" : "document"
            messageContent = content.isEmpty ? "Please analyze this image" : content
        }
        
        // Create and add user message with attachment
        let userMessage = Message(
            content: messageContent,
            isFromUser: true,
            attachmentData: attachmentData,
            attachmentType: attachmentType
        )
        messages.append(userMessage)
        
        print("🟢 User message added to array. Total messages: \(messages.count)")
        
        // Clear attachment after saving to message
        currentAttachment = nil
        
        // Save in background, don't wait
        let messagesToSave = messages
        Task.detached {
            StorageService.shared.saveMessages(messagesToSave)
        }
        
        print("🟢 About to call processUserMessage...")
        
        // Process immediately
        Task {
            await processUserMessage(content: messageContent, attachment: attachmentData)
        }
    }
    
    // MARK: - AI Processing
    
    func processUserMessage(content: String, attachment: Data? = nil) async {
        cleanupOldMessages()
        await MainActor.run { isProcessing = true }
        print("💭 Processing: \(content)")
        
        await MainActor.run {
            isProcessing = true
        }
        print("🔵 isProcessing set to true")
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        // STEP 0: Check if there's an image attachment
        if let imageData = attachment,
           let rawImage = UIImage(data: imageData) {
            
            print("📸 Processing image with Ray's vision")
            
            do {
                // Compress image before analysis
                let image = compressImage(rawImage) ?? rawImage
                let visionResponse = try await OpenAIService.shared.analyzeImage(
                    image: image,
                    prompt: content.isEmpty ? "Please describe this image in detail and answer any questions about it." : content
                )
                
                await MainActor.run {
                    let rayMsg = Message(content: visionResponse, isFromUser: false)
                    messages.append(rayMsg)
                    storageService.saveMessages(messages)
                    isProcessing = false
                }
                return
                
            } catch {
                print("🔴 Vision error: \(error)")
                await MainActor.run {
                    messages.append(Message(content: "I'm having trouble analyzing that image right now. Error: \(error.localizedDescription)", isFromUser: false))
                    isProcessing = false
                }
                return
            }
        }
        // STEP 1: Memory recall FIRST
        let recallKeywords = [
            "what did i", "what was", "recall", "do you remember",
            "what's my", "tell me about my", "what are my",
            "how many", "show me", "find my"
        ]
        let isRecallRequest = recallKeywords.contains { content.lowercased().contains($0) }
        if isRecallRequest {
            print("🧠 Checking memories first...")
            let query = content.lowercased()
            let matchingMemories = memories.filter { memory in
                let mem = memory.content.lowercased()
                return mem.contains(query) ||
                    query.contains(mem.split(separator: " ").first?.lowercased() ?? "")
            }
            if !matchingMemories.isEmpty {
                print("🧠 Found \(matchingMemories.count) matching memories!")
                let memoriesContext = matchingMemories.map { "- \($0.content) (saved to \($0.category.displayName))" }.joined(separator: "\n")
                let memoryPrompt = """
                You are Ray. The user asked: "\(content)"
                
                Here's what I have saved in memory:
                \(memoriesContext)
                
                Answer the user's question using ONLY the information from my memories above.
                Be conversational and natural. Don't mention searching or sources - this is from your memory.
                """
                do {
                    let response = try await OpenAIService.shared.sendChatMessage(
                        messages: [Message(content: content, isFromUser: true)],
                        systemPrompt: memoryPrompt,
                        model: Config.defaultModel
                    )
                    await MainActor.run {
                        messages.append(Message(content: response, isFromUser: false))
                        StorageService.shared.saveMessages(messages)
                        isProcessing = false
                    }
                    // No auto-play
                    return
                } catch {
                    print("🔴 Error using memory: \(error)")
                }
            }
            print("🧠 No memories found, will search...")
        }
        
        // STEP 2: Check for document generation requests
        let docGenerationKeywords = ["create pdf", "generate pdf", "make pdf", "pdf",
                                     "create document", "generate document", "word document", "docx",
                                     "create spreadsheet", "generate spreadsheet", "excel", "csv"]
        
        let needsDocGeneration = docGenerationKeywords.contains(where: { content.lowercased().contains($0) })
        
        if needsDocGeneration {
            print("📄 Document generation request detected")
            await handleDocumentGeneration(query: content)
            return
        }
        
        // STEP 3: Check for email scanning requests
        let emailKeywords = ["scan email", "check email", "email orders", "shopping orders", "track packages"]
        let needsEmailScan = emailKeywords.contains(where: { content.lowercased().contains($0) })
        
        if needsEmailScan {
            print("📧 Email scanning request detected")
            await handleEmailScanning(query: content)
            return
        }
        
        // STEP 4: Aggressive search detection
        let lowerQuery = content.lowercased()
        let realTimeKeywords = [
            "breaking", "current", "latest", "today", "tonight", "now", "recent", "update", "updates",
            "news", "headline", "headlines", "score", "scores", "standings", "ranking", "rankings",
            "stock", "stocks", "price", "prices", "market", "earnings", "forecast", "weather",
            "temperature", "traffic", "availability", "available", "release date", "launch", "schedule"
        ]
        let explicitSearchPhrases = [
            "search the web", "search online", "look this up", "google this", "google that",
            "check the internet", "find online", "web search"
        ]
        let explicitSearchRequest = explicitSearchPhrases.contains(where: { lowerQuery.contains($0) })
        let requiresFreshData = realTimeKeywords.contains(where: { lowerQuery.contains($0) })
        if explicitSearchRequest || requiresFreshData {
            print("🔍 Initiating search for: \(content)")
            await handleGoogleSearchWithSources(for: content)
            return
        }
        
        let lowercasedContent = content.lowercased()
        var rayResponse: String = ""
        
        // Check for memory save requests
        if lowercasedContent.contains("remember") || lowercasedContent.contains("save") {
            print("🟡 MEMORY INTENT detected")
            rayResponse = await handleMemoryIntent(content: content)
            
        } else {
            // Everything else goes to OpenAI - general conversation
            print("🟣 GENERAL CONVERSATION - calling OpenAI")
            
            do {
                print("🟣 About to call OpenAI...")
                
                // Build system prompt with current date
                let currentDate = Date()
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .long
                let dateString = dateFormatter.string(from: currentDate)
                
                // For regular conversation, pass ENTIRE message history to OpenAI
                print("💬 Sending conversation with \(messages.count) messages to OpenAI")
                
                let systemPrompt = """
                    You are Ray, a powerful AI assistant with these capabilities:
                    
                    CORE ABILITIES:
                    - Answer questions using your broad general knowledge first
                    - Use current web search only when the user explicitly asks for it or when the question clearly requires fresh, real-time, or location-specific data
                    - Remember and recall information the user tells you
                    - Generate professional documents (PDF, Word, Excel)
                    - Analyze images and photos
                    - Set reminders and notifications
                    - Provide structured, organized responses
                    
                    DOCUMENT GENERATION:
                    - When asked to create PDF/document/spreadsheet, generate files and format information professionally
                    
                    IMPORTANT PERSONALITY TRAITS:
                    - You NEVER give up or tell users to check elsewhere
                    - You extract and provide ALL relevant information from your own knowledge before considering tools
                    - You are thorough and complete in your answers
                    - You dig deeper when initial results are insufficient
                    - You synthesize information from multiple sources
                    - You provide specific details, names, numbers, and lists when asked
                    
                    SEARCH TOOL USAGE:
                    - Reach for the web/search tool only for news, live scores, prices, weather, availability, schedules, or when the user explicitly asks for an online lookup
                    - If a search returns nothing useful, continue with your best general-knowledge answer instead of apologizing about missing information
                    
                    You maintain conversation context - remember what the user has said previously in this conversation.
                    If the user says "tell me more" or "what about that" or asks follow-up questions, refer back to the previous messages in the conversation.
                    
                    Keep responses organized, friendly, and helpful.
                    Today is \(dateString).
                    """
                    
                // Detect current info requests and enhance with Google Search
                print("🔵 processUserMessage START: '\(content)'")
                
                // Check each keyword individually
                let currentInfoKeywords = ["top", "current", "latest", "rankings", "news", "today", "now"]
                
                print("🔵 Checking for search keywords...")
                for keyword in currentInfoKeywords {
                    if content.lowercased().contains(keyword) {
                        print("✅ FOUND KEYWORD: '\(keyword)' - should trigger search!")
                    }
                }
                
                let needsSearch = currentInfoKeywords.contains(where: { content.lowercased().contains($0) })
                print("🔵 needsSearch = \(needsSearch)")
                
                if needsSearch {
                    print("🔍🔍🔍 TRIGGERING GOOGLE SEARCH 🔍🔍🔍")
                    
                    do {
                        let searchResults = try await GoogleSearchService.shared.search(query: content)
                        
                        guard !searchResults.isEmpty else {
                            print("🔍 No search results found")
                            // Fall back to OpenAI
                            throw NSError(domain: "Search", code: 404, userInfo: nil)
                        }
                        
                        print("🔍 Found \(searchResults.count) results")
                        
                        // Format search results for Ray
                        let resultsContext = searchResults.prefix(5).enumerated().map { index, result in
                            "\(index + 1). \(result.title)\n   \(result.snippet)\n   Source: \(result.link)"
                        }.joined(separator: "\n\n")
                        
                        // Create enhanced prompt with search results
                        let searchPrompt = """
                            You are Ray, a persistent and thorough AI assistant. Today is \(dateString).
                            
                            The user asked: "\(content)"
                            
                            Here are current search results from the web:
                            
                            \(resultsContext)
                            
                            CRITICAL INSTRUCTIONS:
                            - You MUST provide a complete, specific answer based on the search results
                            - NEVER tell the user to "check a website" or "visit a source"
                            - Extract ALL relevant information from the search results
                            - If you see specific details like names, numbers, rankings, addresses, phone numbers - include them ALL
                            - Synthesize information from multiple results to give the most complete answer
                            - Be thorough and detailed - don't hold back information
                            
                            Give the user the ACTUAL answer they're looking for, not a referral to another source.
                            """
                            
                        // Pass full conversation history even with search results
                        let rayResponse = try await OpenAIService.shared.sendChatMessage(
                            messages: messages,  // ← FULL conversation history
                            systemPrompt: searchPrompt,
                            model: Config.defaultModel
                        )
                        
                        print("🔍 Ray response with search context: \(rayResponse)")
                        
                        await MainActor.run {
                            let rayMessage = Message(content: rayResponse, isFromUser: false)
                            messages.append(rayMessage)
                            storageService.saveMessages(messages)
                            isProcessing = false
                        }
                        
                        // No auto-play
                        return
                        
                    } catch {
                        print("🔴 Google search failed: \(error)")
                        print("🔴 Falling back to OpenAI without search")
                        // Continue to normal OpenAI call below
                    }
                }
                
                let selectedModel = selectModel(for: content)
                print("🤖 Selected model: \(selectedModel)")
                
                // CRITICAL: Pass the FULL messages array, not just the last message
                // This gives Ray the entire conversation context
                rayResponse = try await OpenAIService.shared.sendChatMessage(
                    messages: messages,  // ← FULL conversation history
                    systemPrompt: systemPrompt,
                    model: selectedModel
                )
                
                print("💬 Ray's response: \(rayResponse)")
                
                await MainActor.run {
                    let rayMessage = Message(content: rayResponse, isFromUser: false)
                    messages.append(rayMessage)
                    storageService.saveMessages(messages)
                    isProcessing = false
                    print("🟣 Ray message added successfully")
                }
                
                // No auto-play
                
            } catch {
                print("🔴 OpenAI ERROR: \(error)")
                print("🔴 Error type: \(type(of: error))")
                print("🔴 Localized: \(error.localizedDescription)")
                
                await MainActor.run {
                    // Add a visible error message so user knows what happened
                    let errorMsg = Message(content: "I'm having trouble connecting to my brain right now. Error: \(error.localizedDescription)", isFromUser: false)
                    messages.append(errorMsg)
                    isProcessing = false
                }
            }
            
            // Return early after OpenAI call (success or error)
            return
        }
        
        print("🔵 Final rayResponse: '\(rayResponse)'")
        
        // Add Ray's response to messages - on MainActor (for memory/recall intents)
        await MainActor.run {
            let rayMessage = Message(content: rayResponse, isFromUser: false)
            messages.append(rayMessage)
            storageService.saveMessages(messages)
            print("🟣 Ray message added. Total messages: \(messages.count)")
        }
        
        // No auto-play
    }
    
    // MARK: - Model Selection
    
    private func selectModel(for content: String) -> String {
        let lowerContent = content.lowercased()
        
        // Deep think triggers: analysis, research, complex problem-solving
        let deepThinkKeywords = ["analyze", "research", "explain in detail", "deep dive",
                                "comprehensive", "compare and contrast", "pros and cons"]
        
        for keyword in deepThinkKeywords {
            if lowerContent.contains(keyword) {
                print("🧠 Using advanced model for complex task")
                return Config.advancedModel // gpt-4o for complex tasks
            }
        }
        
        // Default: use fastest, cheapest model
        print("⚡ Using default model")
        return Config.defaultModel // gpt-4o-mini
    }
    
    // MARK: - Google Search Handler
    
    private func handleGoogleSearchWithSources(for query: String) async {
        print("🔍 Single search for: \(query)")
        
        await MainActor.run { isProcessing = true }
        
        // Optimize query once
        var optimizedQuery = query
        if query.lowercased().contains("ranking") || query.lowercased().contains("top") {
            optimizedQuery = "\(query) 2025 AP poll current"
        } else if query.lowercased().contains("college football") {
            optimizedQuery = "\(query) AP rankings 2025"
        }
        
        print("🔍 Optimized to: \(optimizedQuery)")
        do {
            // Debug logging
            print("🔍🔍🔍 handleGoogleSearchWithSources CALLED")
            print("🔍 Query: \(query)")
            
            // For debugging, force a concrete query to verify API calls work
            let debugQuery = "AP Top 10 college football poll November 2025"
            print("🔍 Searching Google for: \(debugQuery)")
            let results = try await GoogleSearchService.shared.search(query: debugQuery)
            print("🔍 ✅ Got \(results.count) results from Google")
            if results.isEmpty {
                print("🔍 ❌ NO RESULTS - This is the problem")
            }
            for (index, result) in results.prefix(5).enumerated() {
                print("🔍 Result \(index + 1): \(result.title)")
                print("🔍   Snippet: \(result.snippet)")
            }
            guard !results.isEmpty else {
                print("⚠️ No results - falling back to knowledge")
                await fallbackToKnowledge(query: query)
                return
            }
            let topResults = Array(results.prefix(3))
            let sources: [MessageSource] = topResults.map { MessageSource(title: $0.title, url: $0.link) }
            let resultsContext = topResults.enumerated().map { index, result in
                """
                SOURCE \(index + 1):
                Title: \(result.title)
                Info: \(result.snippet)
                """
            }.joined(separator: "\n\n")
            let currentDate = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            let dateString = dateFormatter.string(from: currentDate)
            let searchPrompt = """
            You are Ray. Today is \(dateString).
            
            User question: "\(query)"
            
            SEARCH RESULTS - USE EXACT INFORMATION:
            \(resultsContext)
            
            CRITICAL RULES:
            1. Copy rankings/names EXACTLY from search results
            2. DO NOT invent teams not in results
            3. Include records if shown (8-0, 9-0, etc)
            4. Start with "Based on current rankings:"
            5. List exactly what search results say
            
            Give ONLY what's in the search results above.
            """
            let rayResponse = try await OpenAIService.shared.sendChatMessage(
                messages: [Message(content: query, isFromUser: true)],
                systemPrompt: searchPrompt,
                model: "gpt-4o"
            )
            // Validation
            let responseTeams = extractTeams(from: rayResponse)
            let searchTeams = extractTeams(from: resultsContext)
            if !responseTeams.isEmpty && !searchTeams.isEmpty {
                let matchCount = responseTeams.filter { searchTeams.contains($0) }.count
                if matchCount < max(1, responseTeams.count / 2) {
                    print("⚠️ WARNING: Ray may be hallucinating - response doesn't match search results")
                }
            }
            await MainActor.run {
                messages.append(Message(content: rayResponse, isFromUser: false, sources: sources))
                storageService.saveMessages(messages)
                isProcessing = false
            }
            return
        } catch {
            print("🔴 Search failed: \(error)")
            await fallbackToKnowledge(query: query)
            return
        }
        
        // legacy multi-attempt code removed
    }
    
    // Helper function to generate search variations
    // optimizeSearchQuery replaces generateSearchVariations to reduce API calls
    private func optimizeSearchQuery(_ query: String) -> String {
        var optimized = query
        if query.lowercased().contains("ranking") || query.lowercased().contains("top") {
            optimized += " 2025 current"
        }
        if query.lowercased().contains("college football") {
            optimized = query.replacingOccurrences(of: "college football teams", with: "college football rankings AP poll")
        }
        return optimized
    }

    private func fallbackToKnowledge(query: String) async {
        print("🧠 Falling back to built-in knowledge for query: \(query)")
        await processWithOpenAI(query, sources: nil)
    }

    private func extractTeams(from text: String) -> Set<String> {
        let pattern = "[A-Z][A-Za-z&.']+(?:\\s+[A-Z][A-Za-z&.']+)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        let tokens = matches.compactMap { match -> String? in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Set(tokens.filter { $0.count > 2 })
    }
    
    // Extract a date-like string from search results for display
    private func extractDateFromResults(_ results: [SearchResult]) -> String {
        for result in results {
            let text = result.title + " " + result.snippet
            let patterns = [
                "November \\d+, 2025",
                "Nov \\d+, 2025",
                "2025",
                "Week \\d+",
                "as of [A-Za-z]+ \\d+"
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range, in: text) {
                    return String(text[range])
                }
            }
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: Date())
    }
    
    private func processWithOpenAI(_ content: String, sources: [MessageSource]?) async {
        // Regular OpenAI processing without search
        do {
            let currentDate = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            let dateString = dateFormatter.string(from: currentDate)
            
            let systemPrompt = """
            You are Ray, a powerful AI assistant with these capabilities:
            
            CORE ABILITIES:
            - Answer questions using your own broad knowledge first
            - Use current web search only when the user explicitly requests it or when the question clearly requires fresh, real-time, or location-specific data
            - Remember and recall information the user tells you
            - Generate professional documents (PDF, Word, Excel)
            - Analyze images and photos
            - Set reminders and notifications
            - Provide structured, organized responses
            
            DOCUMENT GENERATION:
            - When asked to create PDF/document/spreadsheet, generate files and format information professionally
            
            IMPORTANT PERSONALITY TRAITS:
            - You NEVER give up or tell users to check elsewhere
            - You extract and provide ALL relevant information from your own knowledge before deciding to use tools
            - You are thorough and complete in your answers
            - You dig deeper when initial results are insufficient
            - You synthesize information from multiple sources
            - You provide specific details, names, numbers, and lists when asked
            
            SEARCH TOOL USAGE:
            - Reach for the web/search tool only for news, live scores, prices, weather, availability, schedules, or when the user explicitly asks for an online lookup
            - If a search returns nothing useful, continue with your best general-knowledge answer instead of apologizing about missing information
            
            You maintain conversation context - remember what the user has said previously in this conversation.
            If the user says "tell me more" or "what about that" or asks follow-up questions,
            refer back to the previous messages in the conversation.
            
            Keep responses organized, friendly, and helpful.
            Today is \(dateString).
            """
            
            let rayResponse = try await OpenAIService.shared.sendChatMessage(
                messages: messages,
                systemPrompt: systemPrompt,
                model: selectModel(for: content)
            )
            
            await MainActor.run {
                let rayMessage = Message(
                    content: rayResponse,
                    isFromUser: false,
                    sources: sources
                )
                messages.append(rayMessage)
                storageService.saveMessages(messages)
                isProcessing = false
            }
            // No auto-play
        } catch {
            print("🔴 OpenAI error: \(error)")
            await MainActor.run {
                messages.append(Message(content: "I'm having trouble thinking right now. Can you try again?", isFromUser: false))
                isProcessing = false
            }
        }
    }
    
    func showSources(for message: Message) {
        print("📎 Showing sources for message")
        if let sources = message.sources, !sources.isEmpty {
            print("📎 Found \(sources.count) sources")
            selectedMessageSources = sources
            showingSourcesSheet = true
        } else {
            print("📎 No sources found")
        }
    }
    
    // Alias method for compatibility
    func showSourcesSheet(for message: Message) {
        showSources(for: message)
    }
    
    private func handleGoogleSearch(for originalQuery: String) async {
        do {
            // Improve query for specific cases
            var query = originalQuery
            if originalQuery.lowercased().contains("top") && originalQuery.lowercased().contains("college football") {
                // Make query more specific for sports rankings
                query = "AP Top 25 college football rankings current week"
                print("🔍 Using targeted query for sports rankings: \(query)")
            }
            
            print("🔍 Calling GoogleSearchService...")
            let results = try await GoogleSearchService.shared.search(query: query)
            print("🔍 Got \(results.count) results")
            
            // Format results with more detail
            let resultsContext = results.prefix(5).enumerated().map { index, result in
                "\(index + 1). \(result.title)\n   \(result.snippet)\n   Source: \(result.link)"
            }.joined(separator: "\n\n")
            
            let currentDate = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            let dateString = dateFormatter.string(from: currentDate)
            
            let searchPrompt = """
            You are Ray. Today is \(dateString).
            
            The user asked: "\(originalQuery)"
            
            Here are search results from Google:
            
            \(resultsContext)
            
            Based on these search results, provide the most complete answer possible.
            If the search results don't contain full details, acknowledge what you found 
            (like "Ohio State is #1") and note that complete rankings would require visiting 
            the specific sports sites mentioned.
            
            Be helpful and specific with whatever information IS available in the results.
            """
            
            let response = try await OpenAIService.shared.sendChatMessage(
                messages: [Message(content: originalQuery, isFromUser: true)],
                systemPrompt: searchPrompt,
                model: Config.defaultModel
            )
            
            await MainActor.run {
                messages.append(Message(content: response, isFromUser: false))
                isProcessing = false
            }
            // No auto-play
        } catch {
            print("🔴 Search error: \(error)")
            await MainActor.run {
                isProcessing = false
            }
        }
    }
    
    // MARK: - Document Scanning
    
    func scanDocument(_ documentURL: URL) async -> String? {
        // Extract text from PDF/DOCX
        // For now, return filename as placeholder
        return "Document: \(documentURL.lastPathComponent)"
    }
    
    // MARK: - Intent Detection
    
    private func detectIntent(keywords: [String], in content: String) -> Bool {
        keywords.contains { content.contains($0) }
    }
    
    private func detectShoppingIntent(content: String) -> Bool {
        let shoppingKeywords = ["buy", "purchase", "shopping", "find"]
        let productKeywords = ["shoes", "laptop", "phone", "computer", "book", "watch", "headphones", "camera", "tablet", "clothes", "clothing", "dress", "jacket", "bag"]
        
        let hasShoppingKeyword = shoppingKeywords.contains { content.contains($0) }
        let hasProductKeyword = productKeywords.contains { content.contains($0) }
        
        return hasShoppingKeyword && hasProductKeyword
    }
    
    // MARK: - Intent Handlers
    
    private func handleMemoryIntent(content: String) async -> String {
        // Extract what to remember
        let memoryContent = extractMemoryContent(from: content)
        
        // Auto-categorize
        let category = categorizeMemory(memoryContent)
        
        // Save memory
        await MainActor.run {
            saveMemory(content: memoryContent, category: category)
        }
        
        return "Got it! I've saved that to \(category.displayName). 🧠"
    }
    
    private func handleRecallIntent(content: String) -> String {
        // Search through memories for matching content
        let searchTerms = extractSearchTerms(from: content)
        
        for memory in memories {
            let memoryLower = memory.content.lowercased()
            if searchTerms.contains(where: { memoryLower.contains($0.lowercased()) }) {
                return "I remember! \(memory.content) 🧠"
            }
        }
        
        return "I don't have that saved yet. Want me to remember something? 😊"
    }
    
    private func handleCurrentInfoIntent(content: String) async throws -> String {
        let results = try await GoogleSearchService.shared.search(query: content)
        
        guard !results.isEmpty else {
            return "I couldn't find current information about that. Can you try rephrasing your question? 🤔"
        }
        
        // Summarize top 3 results
        let topResults = Array(results.prefix(3))
        var summary = "Here's what I found:\n\n"
        
        for (index, result) in topResults.enumerated() {
            summary += "\(index + 1). \(result.title)\n\(result.snippet)\n\n"
        }
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func handleShoppingIntent(content: String) async throws -> String {
        // Modify query to include shopping context
        let shoppingQuery = content.contains("buy") || content.contains("purchase") 
            ? content 
            : "buy \(content)"
        
        let results = try await GoogleSearchService.shared.search(query: shoppingQuery)
        
        guard !results.isEmpty else {
            return "I couldn't find any products matching that. Can you try a different search? 🛍️"
        }
        
        // Return top 3-5 product results
        let topResults = Array(results.prefix(5))
        var response = "I found these options:\n\n"
        
        for (index, result) in topResults.enumerated() {
            response += "\(index + 1). \(result.title) - \(result.link)\n"
        }
        
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func handleNudgeIntent(content: String) async -> String {
        // Extract time and message from content
        let (time, message) = extractNudgeDetails(from: content)
        
        // Create nudge
        let title = message.isEmpty ? "Reminder" : message
        let isRecurring = content.contains("daily") || content.contains("every day")
        
        await MainActor.run {
            createNudge(title: title, message: message.isEmpty ? content : message, time: time, isRecurring: isRecurring)
        }
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .medium
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: time)
        
        return "I'll remind you! 💊 You'll get a nudge at \(timeString)."
    }
    
    private func handleGeneralConversation(messages: [Message], attachmentFileName: String?) async throws -> String {
        // Build system prompt with attachment context if needed
        var systemPrompt = "You are Ray, a helpful, kind, and compassionate AI assistant in the Dome-AI app. You have a warm personality and genuinely care about helping the user. You remember everything they tell you to remember. You're conversational, friendly, and use natural language. Keep responses concise but thoughtful (2-4 sentences usually). You can be playful and use emojis occasionally. You help users with everyday tasks, answer questions, and provide support."
        
        if let fileName = attachmentFileName {
            systemPrompt += "\n\nThe user has attached a file: \(fileName). Please acknowledge this in your response if relevant."
        }
        
        let response = try await OpenAIService.shared.sendChatMessage(messages: messages, systemPrompt: systemPrompt)
        return response
    }
    
    // MARK: - Helper Methods
    
    private func extractMemoryContent(from content: String) -> String {
        // Try to extract content after keywords like "remember", "save", etc.
        let patterns = ["remember", "save", "store", "don't forget"]
        
        for pattern in patterns {
            if let range = content.range(of: pattern, options: .caseInsensitive) {
                let afterKeyword = String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterKeyword.isEmpty {
                    // Take first sentence or first 200 characters
                    if let sentenceEnd = afterKeyword.firstIndex(of: ".") {
                        return String(afterKeyword[..<sentenceEnd]).trimmingCharacters(in: .whitespaces)
                    }
                    return String(afterKeyword.prefix(200)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // Default: return the content itself
        return content
    }
    
    private func categorizeMemory(_ content: String) -> MemoryCategory {
        let lowercased = content.lowercased()
        
        // Health/exercise/workout keywords
        if lowercased.contains("health") || lowercased.contains("exercise") || lowercased.contains("workout") || 
           lowercased.contains("gym") || lowercased.contains("run") || lowercased.contains("yoga") ||
           lowercased.contains("medication") || lowercased.contains("pill") || lowercased.contains("dose") {
            return .exercise
        }
        
        // Email/contact/address keywords
        if lowercased.contains("email") || lowercased.contains("contact") || lowercased.contains("address") ||
           lowercased.contains("phone") || lowercased.contains("number") || lowercased.contains("@") {
            return .email
        }
        
        // Notes/todo/task keywords
        if lowercased.contains("todo") || lowercased.contains("task") || lowercased.contains("note") ||
           lowercased.contains("reminder") || lowercased.contains("appointment") || lowercased.contains("meeting") {
            return .notes
        }
        
        // Default to brain
        return .brain
    }
    
    private func extractSearchTerms(from content: String) -> [String] {
        // Extract key search terms by removing common question words
        let questionWords = ["what", "did", "i", "was", "do", "you", "remember", "what's", "my"]
        let words = content.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .filter { !questionWords.contains($0) && $0.count > 2 }
        
        return Array(words.prefix(3))
    }
    
    private func extractNudgeDetails(from content: String) -> (Date, String) {
        let calendar = Calendar.current
        var scheduledTime = Date().addingTimeInterval(60 * 60) // Default: 1 hour from now
        var message = ""
        
        // Extract time
        let lowercased = content.lowercased()
        
        if let hourMatch = extractHour(from: lowercased) {
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            
            if lowercased.contains("tomorrow") {
                components.day = (components.day ?? 0) + 1
            }
            
            components.hour = hourMatch
            components.minute = 0
            scheduledTime = calendar.date(from: components) ?? scheduledTime
        } else if let minutesMatch = extractMinutes(from: lowercased) {
            scheduledTime = Date().addingTimeInterval(Double(minutesMatch) * 60)
        } else if lowercased.contains("tomorrow") {
            scheduledTime = calendar.date(byAdding: .day, value: 1, to: scheduledTime) ?? scheduledTime
        }
        
        // Extract message
        if let remindRange = lowercased.range(of: "remind me") {
            let afterRemind = String(content[remindRange.upperBound...])
            // Remove time words
            let cleaned = afterRemind
                .replacingOccurrences(of: "tomorrow", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "in \\d+ (hour|minute)", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !cleaned.isEmpty {
                message = cleaned
            }
        }
        
        return (scheduledTime, message)
    }
    
    private func extractHour(from text: String) -> Int? {
        let patterns = [
            (try? NSRegularExpression(pattern: #"(\d{1,2})\s*(am|pm)"#, options: .caseInsensitive)),
            (try? NSRegularExpression(pattern: #"at\s+(\d{1,2})"#, options: .caseInsensitive))
        ]
        
        for pattern in patterns.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = pattern.firstMatch(in: text, options: [], range: range) {
                if match.numberOfRanges > 1,
                   let hourRange = Range(match.range(at: 1), in: text),
                   let hour = Int(text[hourRange]) {
                    if text.contains("pm") && hour < 12 {
                        return hour + 12
                    } else if text.contains("am") && hour == 12 {
                        return 0
                    }
                    return hour
                }
            }
        }
        
        return nil
    }
    
    private func extractMinutes(from text: String) -> Int? {
        let pattern = try? NSRegularExpression(pattern: #"in\s+(\d+)\s+(minute|hour)"#, options: .caseInsensitive)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        if let match = pattern?.firstMatch(in: text, options: [], range: range),
           match.numberOfRanges > 1,
           let numberRange = Range(match.range(at: 1), in: text),
           let number = Int(text[numberRange]) {
            if text.contains("hour") {
                return number * 60
            }
            return number
        }
        
        return nil
    }
    
    // MARK: - Image Compression
    private func compressImage(_ image: UIImage) -> UIImage? {
        let maxSize: CGFloat = 1024
        let scale = min(maxSize / image.size.width, maxSize / image.size.height)
        if scale < 1 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resized
        }
        return image
    }
    
    // MARK: - Memory cleanup
    private func cleanupOldMessages() {
        if messages.count > 50 {
            messages = Array(messages.suffix(50))
            StorageService.shared.saveMessages(messages)
        }
    }
    
    // MARK: - Report Generation Methods (TODO: Implement)
    
    /// Generate PDF report from content
    /// TODO: Generate PDF report
    func generatePDF(content: String) -> URL? {
        // TODO: Implement PDF generation using PDFKit or similar
        return nil
    }
    
    /// Generate Word document from content
    /// TODO: Generate Word doc
    func generateDOCX(content: String) -> URL? {
        // TODO: Implement DOCX generation
        return nil
    }
    
    /// Generate Excel file from data
    /// TODO: Generate Excel file
    func generateXLSX(data: [[String]]) -> URL? {
        // TODO: Implement XLSX generation
        return nil
    }
    
    // MARK: - #DATA Command Handler
    
    private func handleDataCommand(content: String) -> String {
        // TODO: Enhance saveMemory() to support #DATA command recall
        // Extract data command and search brain memories
        let searchTerms = extractSearchTerms(from: content)
        
        for memory in memories {
            let memoryLower = memory.content.lowercased()
            if searchTerms.contains(where: { memoryLower.contains($0.lowercased()) }) {
                return "Here's what I found: \(memory.content) 🧠"
            }
        }
        
        return "I don't have that data stored yet. Want me to remember something? 😊"
    }
    
    // MARK: - Future Features (TODO Comments)
    
    // TODO: Gmail/Outlook email integration
    // TODO: Calendar access ("what's coming up today")
    // TODO: Apple Watch data integration
    // TODO: Photo analysis (calorie estimates, object identification)
    // TODO: Shopping tracking (orders, deliveries, budgeting)
    // TODO: Step-by-step app guidance
    // TODO: Conversational context retention
    
    // MARK: - Voice Input
    
    func startVoiceInput() {
        Task {
            await speechService.startRecording()
            await MainActor.run {
                isRecording = speechService.isRecording
            }
        }
    }
    
    func stopVoiceInput() {
        Task {
            let recognizedTextValue = await MainActor.run { () -> String in
                speechService.stopRecording()
                let text = speechService.recognizedText
                speechService.recognizedText = ""
                isRecording = false
                recognizedText = ""
                return text
            }
            
            let trimmed = recognizedTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                await MainActor.run {
                    sendMessage(content: trimmed)
                }
            }
        }
    }
    
    // MARK: - Memory Management
    
    func saveMemory(content: String, category: MemoryCategory) {
        let memory = Memory(content: content, category: category)
        memories.append(memory)
        storageService.saveMemory(memory)
        print("✅ Saved memory: \(content.prefix(50))...")
    }
    
    // TODO: Enhance saveMemory() to support #DATA command recall
    // This will allow structured data storage and retrieval
    
    func deleteMemory(_ memory: Memory) {
        memories.removeAll { $0.id == memory.id }
        storageService.deleteMemory(memory)
        print("✅ Deleted memory: \(memory.content.prefix(50))...")
    }
    
    func loadMemoriesFromStorage() {
        memories = storageService.loadMemories()
    }
    
    func loadMessagesFromStorage() {
        messages = storageService.loadMessages()
    }

    @MainActor
    func refreshData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let loadedMessages = storageService.loadMessages()
        let loadedMemories = storageService.loadMemories()
        
        messages = loadedMessages
        memories = loadedMemories
        
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    
    func saveMessagesToStorage() {
        storageService.saveMessages(messages)
    }
    
    // MARK: - Attachment Management
    
    func attachFile(_ attachment: Attachment) {
        currentAttachment = attachment
        print("✅ Attachment attached: \(attachment.fileName)")
    }
    
    func removeAttachment() {
        currentAttachment = nil
        print("🗑️ Attachment removed")
    }

    func clearAllMessages() {
        messages.removeAll()
        storageService.saveMessages(messages)
        print("🧹 Cleared all chat messages")
    }

    func deleteMessage(id: UUID) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages.remove(at: index)
            storageService.saveMessages(messages)
            print("🗑️ Deleted message with id: \(id)")
        } else {
            print("⚠️ Unable to find message with id: \(id) to delete")
        }
    }
    
    // MARK: - Document Generation
    
    private func handleDocumentGeneration(query: String) async {
        await MainActor.run { isProcessing = true }
        
        // Get the content to put in the document (from last Ray message)
        guard let lastRayMessage = messages.last(where: { !$0.isFromUser }) else {
            await MainActor.run {
                messages.append(Message(content: "I don't have any content to create a document from. Could you ask me a question first, then request a document?", isFromUser: false))
                isProcessing = false
            }
            return
        }
        
        let content = lastRayMessage.content
        let title = "Ray_Analysis_\(Date())"
        
        var generatedURL: URL?
        var fileType = ""
        
        // Determine which type of document
        if query.lowercased().contains("pdf") {
            generatedURL = DocumentGenerationService.shared.generatePDF(content: content, title: title)
            fileType = "PDF"
        } else if query.lowercased().contains("word") || query.lowercased().contains("document") || query.lowercased().contains("docx") {
            generatedURL = DocumentGenerationService.shared.generateDOCX(content: content, title: title)
            fileType = "document"
        } else if query.lowercased().contains("spreadsheet") || query.lowercased().contains("excel") || query.lowercased().contains("csv") {
            // For spreadsheet, we'd need structured data
            // For now, create a simple one
            let data = [["Content"], [content]]
            generatedURL = DocumentGenerationService.shared.generateSpreadsheet(data: data, title: title, headers: ["Analysis"])
            fileType = "spreadsheet"
        }
        
        await MainActor.run {
            if let url = generatedURL {
                let response = "I've created a \(fileType) for you! Tap the share button below to save or share it."
                messages.append(Message(content: response, isFromUser: false))
                
                // Share the file immediately
                DocumentGenerationService.shared.shareFile(url: url)
            } else {
                messages.append(Message(content: "I had trouble creating that \(fileType). Please try again.", isFromUser: false))
            }
            isProcessing = false
        }
    }
    
    // MARK: - Email Scanning
    
    private func handleEmailScanning(query: String) async {
        await MainActor.run { isProcessing = true }
        
        // Check if email access is available
        let hasAccess = await EmailScanningService.shared.requestEmailAccess()
        
        await MainActor.run {
            if hasAccess {
                messages.append(Message(content: "I'm scanning your emails for shopping and order information...", isFromUser: false))
                // TODO: Actually scan emails when API is integrated
            } else {
                messages.append(Message(content: "I need permission to access your emails for that. Email integration requires connecting your Gmail or Outlook account. Would you like me to guide you through setting that up?", isFromUser: false))
            }
            isProcessing = false
        }
    }
    
    // MARK: - Nudge Management
    
    func createNudge(title: String, message: String, time: Date, isRecurring: Bool = false) {
        let recurrenceType: RecurrenceType = isRecurring ? .daily : .daily
        let nudge = Nudge(
            title: title,
            message: message,
            scheduledTime: time,
            isRecurring: isRecurring,
            recurrenceType: recurrenceType
        )
        
        nudges.append(nudge)
        storageService.saveNudges(nudges)
        notificationService.scheduleNudge(nudge)
        print("✅ Created nudge: \(title) scheduled for \(time)")
    }
}
