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
    private let searchService = DomeSearchService.shared
    private let calendarService = DomeCalendarService.shared
    private let taskService = DomeTaskService.shared
    
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
        // RAY_MEMORY_SAVE_DETECTION_START
        // CRITICAL: Detect "remember" commands BEFORE doing anything else
        let rememberKeywords = ["remember", "save this", "keep this", "don't forget", "store this", "note this"]
        let isRememberRequest = rememberKeywords.contains { content.lowercased().contains($0) }
        
        if isRememberRequest {
            print("💾 User wants Ray to remember something")
            
            var contentToSave = content
            for keyword in rememberKeywords {
                contentToSave = contentToSave.replacingOccurrences(of: keyword, with: "", options: .caseInsensitive)
            }
            contentToSave = contentToSave.trimmingCharacters(in: .whitespacesAndNewlines)
            if contentToSave.isEmpty {
                contentToSave = extractMemoryContent(from: content)
            }
            if contentToSave.isEmpty {
                contentToSave = content
            }
            
            let autoTags = extractHashtags(from: content)
            let category = inferCategory(from: contentToSave)
            let memory = Memory(content: contentToSave, category: category, tags: autoTags)
            memories.append(memory)
            storageService.saveMemories(memories)
            
            print("✅ Ray saved to memory: \(contentToSave.prefix(50))... with tags: \(autoTags)")
            
            await MainActor.run {
                let confirmationMessage = "Got it! I've saved that to my memory. 🧠"
                messages.append(Message(content: confirmationMessage, isFromUser: false))
                storageService.saveMessages(messages)
                isProcessing = false
            }
            return
        }
        // RAY_MEMORY_SAVE_DETECTION_END
        
        // DOME_INTENT_DETECTION_START
        let lowerContent = content.lowercased()
        
        if lowerContent.contains("calendar") || lowerContent.contains("upcoming events") {
            let response = rayGetUpcomingEvents()
            await MainActor.run {
                messages.append(Message(content: response, isFromUser: false))
                storageService.saveMessages(messages)
                isProcessing = false
            }
            return
        }
        
        if lowerContent.contains("tasks") || lowerContent.contains("to do") {
            let response = rayGetActiveTasks()
            await MainActor.run {
                messages.append(Message(content: response, isFromUser: false))
                storageService.saveMessages(messages)
                isProcessing = false
            }
            return
        }
        // DOME_INTENT_DETECTION_END
        
        // RAY_MEMORY_RECALL_UPGRADE_START
        print("🧠 Ray checking memory for: \(content)")
        
        let allMemories = memories
        let query = content.lowercased()
        var relevantMemories: [Memory] = []
        
        for memory in allMemories {
            let memoryContent = memory.content.lowercased()
            let queryWords = query.split(separator: " ").map { String($0) }
            
            for word in queryWords where word.count > 3 {
                if memoryContent.contains(word) {
                    relevantMemories.append(memory)
                    break
                }
            }
        }
        
        if query.contains("my name") || query.contains("who am i") || query.contains("what's my name") {
            let nameMemories = allMemories.filter { memory in
                let content = memory.content.lowercased()
                return content.contains("name") || content.contains("call me") || content.contains("i am") || content.contains("i'm")
            }
            relevantMemories.append(contentsOf: nameMemories)
        }
        
        if query.contains("what did") || query.contains("do you remember") || query.contains("did i tell you") {
            relevantMemories.append(contentsOf: allMemories.suffix(10))
        }
        
        var uniqueMemories: [UUID: Memory] = [:]
        for memory in relevantMemories {
            uniqueMemories[memory.id] = memory
        }
        relevantMemories = Array(uniqueMemories.values)
        
        if !relevantMemories.isEmpty {
            print("🧠 Found \(relevantMemories.count) relevant memories!")
            
            let memoriesContext = relevantMemories.map { memory -> String in
                var line = "- \(memory.content) (Category: \(memory.category.displayName)"
                let tags = memory.tags.joined(separator: ", ")
                if !tags.isEmpty {
                    line += ", Tags: \(tags)"
                }
                line += ")"
                return line
            }.joined(separator: "\n")
            
            let memoryPrompt = """
            You are Ray, the user's personal AI assistant in DomeAI.
            
            The user asked: "\(content)"
            
            Here is relevant information I have in my memory about the user:
            \(memoriesContext)
            
            CRITICAL INSTRUCTIONS:
            1. Answer the user's question ONLY using the information from my memory above
            2. Be specific and direct - if they asked for their name, give their name
            3. Do NOT say "I don't have access" or "I can't remember" - the information is RIGHT THERE in my memory
            4. Be conversational and friendly, like a personal assistant who knows them well
            5. If the memory contains the exact answer, give it immediately
            
            Answer naturally and personally, as if you remember them.
            """
            
            do {
                let response = try await OpenAIService.shared.sendChatMessage(
                    messages: [Message(content: content, isFromUser: true)],
                    systemPrompt: memoryPrompt,
                    model: Config.defaultModel
                )
                
                await MainActor.run {
                    messages.append(Message(content: response, isFromUser: false))
                    storageService.saveMessages(messages)
                    isProcessing = false
                }
                return
            } catch {
                print("🔴 Error using memory to answer: \(error)")
            }
        } else {
            print("🧠 No relevant memories found for this query")
        }
        // RAY_MEMORY_RECALL_UPGRADE_END
        
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
        
        // RAY_CONVERSATION_CONTEXT_START
        let recentMessages = Array(messages.suffix(10))
        
        let raySystemPrompt = """
        You are Ray, a friendly, sharp, and helpful personal AI assistant living inside DomeAI.
        
        PERSONALITY:
        - You are warm, conversational, and supportive
        - You remember context within conversations
        - You give clear, concise answers (2-4 sentences typically)
        - You're proactive about helping the user stay organized
        
        CAPABILITIES YOU HAVE ACCESS TO:
        - Memory system: User can ask you to remember things, and you save them
        - Calendar: User can ask about upcoming events
        - Tasks: User can ask about their to-do items
        - You search your internal database before answering
        
        IMPORTANT:
        - Maintain conversational context - remember what was said earlier in THIS conversation
        - Be specific and direct with answers
        - If you don't know something, be honest but helpful
        
        Answer naturally and conversationally.
        """
        
        do {
            let response = try await OpenAIService.shared.sendChatMessage(
                messages: recentMessages.isEmpty ? messages : recentMessages,
                systemPrompt: raySystemPrompt,
                model: Config.defaultModel
            )
            
            await MainActor.run {
                messages.append(Message(content: response, isFromUser: false))
                storageService.saveMessages(messages)
                isProcessing = false
            }
        } catch {
            print("🔴 Error calling OpenAI: \(error)")
            await MainActor.run {
                messages.append(Message(content: "I'm having trouble processing that right now. Error: \(error.localizedDescription)", isFromUser: false))
                storageService.saveMessages(messages)
                isProcessing = false
            }
        }
        // RAY_CONVERSATION_CONTEXT_END
        return
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
    
    // DOME_RAY_INTELLIGENCE_START
    
    private func rayRecall(query: String) -> String {
        print("🧠 Ray recalling: \(query)")
        let searchResults = searchService.searchAll(query: query)
        guard !searchResults.isEmpty else {
            return "I don't have any saved information about that yet. Would you like me to remember something?"
        }
        
        var response = "Here's what I found in my memory:\n\n"
        let limit = min(searchResults.count, 5)
        for index in 0..<limit {
            let result = searchResults[index]
            response += "\(result.emoji) \(result.title)\n"
            if let subtitle = result.subtitle, !subtitle.isEmpty {
                response += "   \(subtitle)\n"
            }
            let tagsText = result.tags.joined(separator: ", ")
            if !tagsText.isEmpty {
                response += "   Tags: \(tagsText)\n"
            }
            if index < limit - 1 {
                response += "\n"
            }
        }
        if searchResults.count > limit {
            response += "\n...and \(searchResults.count - limit) more results."
        }
        return response
    }
    
    private func rayRemember(content: String, tags: [String], category: MemoryCategory) {
        let memory = Memory(content: content, category: category, tags: tags)
        memories.append(memory)
        storageService.saveMemory(memory)
        print("✅ Ray remembered: \(content.prefix(50))...")
    }
    
    private func raySearchByTag(tag: String) -> [DomeSearchResult] {
        print("🏷️ Ray searching tag: \(tag)")
        return searchService.searchByTag(tag)
    }
    
    private func rayGetUpcomingEvents() -> String {
        let events = calendarService.getUpcomingEvents(limit: 5)
        guard !events.isEmpty else {
            return "You don't have any upcoming events scheduled."
        }
        
        var response = "Here are your upcoming events:\n\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let count = min(events.count, 5)
        for index in 0..<count {
            let event = events[index]
            response += "📅 \(event.title)\n"
            response += "   \(dateFormatter.string(from: event.startDate))\n"
            if let notes = event.notes, !notes.isEmpty {
                response += "   \(notes)\n"
            }
            let tagsText = event.tags.joined(separator: ", ")
            if !tagsText.isEmpty {
                response += "   Tags: \(tagsText)\n"
            }
            if index < count - 1 {
                response += "\n"
            }
        }
        if events.count > count {
            response += "\n...and \(events.count - count) more events."
        }
        return response
    }
    
    private func rayGetActiveTasks() -> String {
        let tasks = taskService.getActiveTasks()
        guard !tasks.isEmpty else {
            return "You're all caught up! No active tasks."
        }
        
        var response = "Here are your active tasks:\n\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        let count = min(tasks.count, 10)
        for index in 0..<count {
            let task = tasks[index]
            response += "\(task.priority.emoji) \(task.title)\n"
            if let dueDate = task.dueDate {
                response += "   Due: \(dateFormatter.string(from: dueDate))\n"
            }
            if let notes = task.notes, !notes.isEmpty {
                response += "   \(notes)\n"
            }
            let tagsText = task.tags.joined(separator: ", ")
            if !tagsText.isEmpty {
                response += "   Tags: \(tagsText)\n"
            }
            if index < count - 1 {
                response += "\n"
            }
        }
        if tasks.count > count {
            response += "\n...and \(tasks.count - count) more tasks."
        }
        return response
    }
    
    // DOME_RAY_INTELLIGENCE_END
    
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
    
    private func extractTags(from content: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "#(\\w+)", options: .caseInsensitive)
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        var tags: [String] = []
        if let matches = pattern?.matches(in: content, options: [], range: nsRange) {
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    tags.append(String(content[range]).lowercased())
                }
            }
        }
        return Array(Set(tags))
    }
    
    // RAY_MEMORY_HELPERS_START
    private func extractHashtags(from text: String) -> [String] {
        let pattern = "#\\w+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range]).replacingOccurrences(of: "#", with: "")
        }
    }
    
    private func inferCategory(from content: String) -> MemoryCategory {
        let lowercased = content.lowercased()
        
        if lowercased.contains("doctor") || lowercased.contains("appointment") || lowercased.contains("medicine") {
            return .doctor
        } else if lowercased.contains("work") || lowercased.contains("meeting") || lowercased.contains("project") {
            return .work
        } else if lowercased.contains("recipe") || lowercased.contains("cook") || lowercased.contains("ingredients") {
            return .recipes
        } else if lowercased.contains("buy") || lowercased.contains("shopping") || lowercased.contains("purchase") {
            return .shopping
        } else if lowercased.contains("exercise") || lowercased.contains("workout") || lowercased.contains("fitness") {
            return .exercise
        } else if lowercased.contains("http") || lowercased.contains("www") || lowercased.contains(".com") {
            return .links
        } else if lowercased.contains("task") || lowercased.contains("todo") || lowercased.contains("need to") {
            return .tasks
        } else if lowercased.contains("note") {
            return .notes
        } else {
            return categorizeMemory(content)
        }
    }
    // RAY_MEMORY_HELPERS_END
    
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
    
    // RAY_MEMORY_DEBUG_START
    func debugPrintMemories() {
        print("=== RAY'S MEMORY DEBUG ===")
        print("Total memories: \(memories.count)")
        for (index, memory) in memories.enumerated() {
            print("\(index + 1). [\(memory.category.displayName)] \(memory.content)")
            if !memory.tags.isEmpty {
                print("   Tags: \(memory.tags.joined(separator: ", "))")
            }
        }
        print("========================")
    }
    // RAY_MEMORY_DEBUG_END
    
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
