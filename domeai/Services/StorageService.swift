//
//  StorageService.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation

class StorageService {
    static let shared = StorageService()
    
    private let fileManager = FileManager.default
    private let memoriesFileName = "memories.json"
    private let messagesFileName = "chatHistory.json"
    private let nudgesFileName = "nudges.json"
    private let eventsFileName = "domeEvents.json"
    private let tasksFileName = "domeTasks.json"
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var memoriesURL: URL {
        documentsDirectory.appendingPathComponent(memoriesFileName)
    }
    
    private var messagesURL: URL {
        documentsDirectory.appendingPathComponent(messagesFileName)
    }
    
    private var nudgesURL: URL {
        documentsDirectory.appendingPathComponent(nudgesFileName)
    }
    
    private var eventsURL: URL {
        documentsDirectory.appendingPathComponent(eventsFileName)
    }
    
    private var tasksURL: URL {
        documentsDirectory.appendingPathComponent(tasksFileName)
    }
    
    private init() {}
    
    // MARK: - Messages
    
    func saveMessages(_ messages: [Message]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(messages)
            try data.write(to: messagesURL)
            print("✅ Successfully saved \(messages.count) message(s) to \(messagesFileName)")
        } catch {
            print("❌ Failed to save messages: \(error.localizedDescription)")
        }
    }
    
    func loadMessages() -> [Message] {
        do {
            guard fileManager.fileExists(atPath: messagesURL.path) else {
                print("ℹ️ Messages file does not exist, returning empty array")
                return []
            }
            
            let data = try Data(contentsOf: messagesURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let messages = try decoder.decode([Message].self, from: data)
            print("✅ Successfully loaded \(messages.count) message(s) from \(messagesFileName)")
            return messages
        } catch {
            print("❌ Failed to load messages: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Memories
    
    func saveMemories(_ memories: [Memory]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(memories)
            try data.write(to: memoriesURL)
            print("✅ Successfully saved \(memories.count) memories to \(memoriesFileName)")
        } catch {
            print("❌ Failed to save memories: \(error.localizedDescription)")
        }
    }
    
    func loadMemories() -> [Memory] {
        do {
            guard fileManager.fileExists(atPath: memoriesURL.path) else {
                print("ℹ️ Memories file does not exist, returning empty array")
                return []
            }
            
            let data = try Data(contentsOf: memoriesURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let memories = try decoder.decode([Memory].self, from: data)
            print("✅ Successfully loaded \(memories.count) memories from \(memoriesFileName)")
            return memories
        } catch {
            print("❌ Failed to load memories: \(error.localizedDescription)")
            return []
        }
    }
    
    func saveMemory(_ memory: Memory) {
        var memories = loadMemories()
        memories.append(memory)
        saveMemories(memories)
        print("✅ Successfully appended and saved memory with id: \(memory.id)")
    }
    
    func loadMemories(by category: MemoryCategory) -> [Memory] {
        let allMemories = loadMemories()
        return allMemories.filter { $0.category == category }
    }
    
    func deleteMemory(_ memory: Memory) {
        var memories = loadMemories()
        memories.removeAll { $0.id == memory.id }
        saveMemories(memories)
        print("✅ Successfully deleted memory with id: \(memory.id)")
    }
    
    // MARK: - Nudges
    
    func saveNudges(_ nudges: [Nudge]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(nudges)
            try data.write(to: nudgesURL)
            print("✅ Successfully saved \(nudges.count) nudges to \(nudgesFileName)")
        } catch {
            print("❌ Failed to save nudges: \(error.localizedDescription)")
        }
    }
    
    func loadNudges() -> [Nudge] {
        do {
            guard fileManager.fileExists(atPath: nudgesURL.path) else {
                print("ℹ️ Nudges file does not exist, returning empty array")
                return []
            }
            
            let data = try Data(contentsOf: nudgesURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let nudges = try decoder.decode([Nudge].self, from: data)
            print("✅ Successfully loaded \(nudges.count) nudges from \(nudgesFileName)")
            return nudges
        } catch {
            print("❌ Failed to load nudges: \(error.localizedDescription)")
            return []
        }
    }
    
    // DOME_STORAGE_EXPANSION
    // MARK: - Dome Events
    
    func saveDomeEvents(_ events: [DomeEvent]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(events)
            try data.write(to: eventsURL)
            print("✅ Successfully saved \(events.count) Dome events")
        } catch {
            print("❌ Failed to save Dome events: \(error.localizedDescription)")
        }
    }
    
    func loadDomeEvents() -> [DomeEvent] {
        do {
            guard fileManager.fileExists(atPath: eventsURL.path) else {
                print("ℹ️ Dome events file does not exist, returning empty array")
                return []
            }
            
            let data = try Data(contentsOf: eventsURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let events = try decoder.decode([DomeEvent].self, from: data)
            print("✅ Successfully loaded \(events.count) Dome events")
            return events
        } catch {
            print("❌ Failed to load Dome events: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Dome Tasks
    
    func saveDomeTasks(_ tasks: [DomeTask]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(tasks)
            try data.write(to: tasksURL)
            print("✅ Successfully saved \(tasks.count) Dome tasks")
        } catch {
            print("❌ Failed to save Dome tasks: \(error.localizedDescription)")
        }
    }
    
    func loadDomeTasks() -> [DomeTask] {
        do {
            guard fileManager.fileExists(atPath: tasksURL.path) else {
                print("ℹ️ Dome tasks file does not exist, returning empty array")
                return []
            }
            
            let data = try Data(contentsOf: tasksURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let tasks = try decoder.decode([DomeTask].self, from: data)
            print("✅ Successfully loaded \(tasks.count) Dome tasks")
            return tasks
        } catch {
            print("❌ Failed to load Dome tasks: \(error.localizedDescription)")
            return []
        }
    }
}
