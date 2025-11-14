//
//  DomeSearchService.swift
//  domeai
//
//  Unified search across all Dome data: memories, events, tasks, tags
//

import Foundation

// DOME_SEARCH_SERVICE_START
struct DomeSearchResult: Identifiable {
    let id = UUID()
    let type: ResultType
    let title: String
    let subtitle: String?
    let tags: [String]
    let date: Date
    let relevanceScore: Double
    let sourceId: UUID
    
    enum ResultType: String {
        case memory
        case event
        case task
        case note
    }
    
    var emoji: String {
        switch type {
        case .memory: return "🧠"
        case .event: return "📅"
        case .task: return "✅"
        case .note: return "📝"
        }
    }
}

class DomeSearchService {
    static let shared = DomeSearchService()
    
    private let storageService = StorageService.shared
    
    private init() {}
    
    func searchAll(query: String) -> [DomeSearchResult] {
        let lowercaseQuery = query.lowercased()
        var results: [DomeSearchResult] = []
        
        let memories = storageService.loadMemories()
        for memory in memories {
            if matchesQuery(memory, query: lowercaseQuery) {
                let result = DomeSearchResult(
                    type: .memory,
                    title: memory.content,
                    subtitle: memory.category.displayName,
                    tags: memory.tags,
                    date: memory.timestamp,
                    relevanceScore: calculateRelevance(memory, query: lowercaseQuery),
                    sourceId: memory.id
                )
                results.append(result)
            }
        }
        
        let events = storageService.loadDomeEvents()
        for event in events {
            if matchesQuery(event, query: lowercaseQuery) {
                let result = DomeSearchResult(
                    type: .event,
                    title: event.title,
                    subtitle: event.notes,
                    tags: event.tags,
                    date: event.startDate,
                    relevanceScore: calculateRelevance(event, query: lowercaseQuery),
                    sourceId: event.id
                )
                results.append(result)
            }
        }
        
        let tasks = storageService.loadDomeTasks()
        for task in tasks {
            if matchesQuery(task, query: lowercaseQuery) {
                let result = DomeSearchResult(
                    type: .task,
                    title: task.title,
                    subtitle: task.notes,
                    tags: task.tags,
                    date: task.dueDate ?? task.createdAt,
                    relevanceScore: calculateRelevance(task, query: lowercaseQuery),
                    sourceId: task.id
                )
                results.append(result)
            }
        }
        
        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    func searchByTag(_ tag: String) -> [DomeSearchResult] {
        var results: [DomeSearchResult] = []
        
        let memories = storageService.loadMemories().filter { $0.tags.contains(tag) }
        for memory in memories {
            results.append(DomeSearchResult(
                type: .memory,
                title: memory.content,
                subtitle: memory.category.displayName,
                tags: memory.tags,
                date: memory.timestamp,
                relevanceScore: 1.0,
                sourceId: memory.id
            ))
        }
        
        let events = storageService.loadDomeEvents().filter { $0.tags.contains(tag) }
        for event in events {
            results.append(DomeSearchResult(
                type: .event,
                title: event.title,
                subtitle: event.notes,
                tags: event.tags,
                date: event.startDate,
                relevanceScore: 1.0,
                sourceId: event.id
            ))
        }
        
        let tasks = storageService.loadDomeTasks().filter { $0.tags.contains(tag) }
        for task in tasks {
            results.append(DomeSearchResult(
                type: .task,
                title: task.title,
                subtitle: task.notes,
                tags: task.tags,
                date: task.dueDate ?? task.createdAt,
                relevanceScore: 1.0,
                sourceId: task.id
            ))
        }
        
        return results.sorted { $0.date > $1.date }
    }
    
    func getAllTags() -> [String] {
        var allTags = Set<String>()
        
        storageService.loadMemories().forEach { allTags.formUnion($0.tags) }
        storageService.loadDomeEvents().forEach { allTags.formUnion($0.tags) }
        storageService.loadDomeTasks().forEach { allTags.formUnion($0.tags) }
        
        return Array(allTags).sorted()
    }
    
    private func matchesQuery(_ memory: Memory, query: String) -> Bool {
        memory.content.lowercased().contains(query) ||
        memory.category.rawValue.lowercased().contains(query) ||
        memory.tags.contains(where: { $0.lowercased().contains(query) })
    }
    
    private func matchesQuery(_ event: DomeEvent, query: String) -> Bool {
        event.title.lowercased().contains(query) ||
        (event.notes?.lowercased().contains(query) ?? false) ||
        event.tags.contains(where: { $0.lowercased().contains(query) })
    }
    
    private func matchesQuery(_ task: DomeTask, query: String) -> Bool {
        task.title.lowercased().contains(query) ||
        (task.notes?.lowercased().contains(query) ?? false) ||
        task.tags.contains(where: { $0.lowercased().contains(query) })
    }
    
    private func calculateRelevance(_ memory: Memory, query: String) -> Double {
        var score = 0.0
        if memory.content.lowercased().hasPrefix(query) { score += 2.0 }
        else if memory.content.lowercased().contains(query) { score += 1.0 }
        if memory.tags.contains(where: { $0.lowercased() == query }) { score += 3.0 }
        return score
    }
    
    private func calculateRelevance(_ event: DomeEvent, query: String) -> Double {
        var score = 0.0
        if event.title.lowercased().hasPrefix(query) { score += 2.0 }
        else if event.title.lowercased().contains(query) { score += 1.0 }
        if event.tags.contains(where: { $0.lowercased() == query }) { score += 3.0 }
        return score
    }
    
    private func calculateRelevance(_ task: DomeTask, query: String) -> Double {
        var score = 0.0
        if task.title.lowercased().hasPrefix(query) { score += 2.0 }
        else if task.title.lowercased().contains(query) { score += 1.0 }
        if task.tags.contains(where: { $0.lowercased() == query }) { score += 3.0 }
        return score
    }
}
// DOME_SEARCH_SERVICE_END

