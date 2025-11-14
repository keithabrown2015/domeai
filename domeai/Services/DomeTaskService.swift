//
//  DomeTaskService.swift
//  domeai
//
//  Dome's internal task service - manages all tasks
//

import Foundation

class DomeTaskService {
    static let shared = DomeTaskService()
    
    private let storageService = StorageService.shared
    private let notificationService = NotificationService.shared
    
    private init() {}
    
    // DOME_TASK_SERVICE_START
    
    func createTask(_ task: DomeTask) {
        var tasks = storageService.loadDomeTasks()
        tasks.append(task)
        storageService.saveDomeTasks(tasks)
        
        if let reminderDate = task.reminderDate {
            scheduleTaskReminder(task, at: reminderDate)
        }
        
        print("✅ Created Dome task: \(task.title)")
    }
    
    func updateTask(_ updatedTask: DomeTask) {
        var tasks = storageService.loadDomeTasks()
        if let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) {
            tasks[index] = updatedTask
            storageService.saveDomeTasks(tasks)
            
            if let oldIdentifier = updatedTask.notificationIdentifier {
                notificationService.cancelNotification(identifier: oldIdentifier)
            }
            if let reminderDate = updatedTask.reminderDate, !updatedTask.isCompleted {
                scheduleTaskReminder(updatedTask, at: reminderDate)
            }
            
            print("✅ Updated Dome task: \(updatedTask.title)")
        }
    }
    
    func completeTask(_ taskId: UUID) {
        var tasks = storageService.loadDomeTasks()
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].isCompleted = true
            tasks[index].completedAt = Date()
            tasks[index].updatedAt = Date()
            storageService.saveDomeTasks(tasks)
            
            if let identifier = tasks[index].notificationIdentifier {
                notificationService.cancelNotification(identifier: identifier)
            }
            
            print("✅ Completed Dome task: \(tasks[index].title)")
        }
    }
    
    func deleteTask(_ task: DomeTask) {
        var tasks = storageService.loadDomeTasks()
        tasks.removeAll { $0.id == task.id }
        storageService.saveDomeTasks(tasks)
        
        if let identifier = task.notificationIdentifier {
            notificationService.cancelNotification(identifier: identifier)
        }
        
        print("✅ Deleted Dome task: \(task.title)")
    }
    
    func getActiveTasks() -> [DomeTask] {
        let tasks = storageService.loadDomeTasks()
        return tasks
            .filter { !$0.isCompleted }
            .sorted { task1, task2 in
                if task1.priority != task2.priority {
                    return task1.priority.rawValue > task2.priority.rawValue
                }
                if let date1 = task1.dueDate, let date2 = task2.dueDate {
                    return date1 < date2
                }
                return task1.dueDate != nil
            }
    }
    
    func getCompletedTasks() -> [DomeTask] {
        let tasks = storageService.loadDomeTasks()
        return tasks
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }
    
    func getOverdueTasks() -> [DomeTask] {
        let tasks = storageService.loadDomeTasks()
        let now = Date()
        return tasks.filter { task in
            !task.isCompleted && (task.dueDate ?? .distantFuture) < now
        }
    }
    
    func searchTasks(query: String) -> [DomeTask] {
        let tasks = storageService.loadDomeTasks()
        let lowercaseQuery = query.lowercased()
        return tasks.filter { task in
            task.title.lowercased().contains(lowercaseQuery) ||
            (task.notes?.lowercased().contains(lowercaseQuery) ?? false) ||
            task.tags.contains(where: { $0.lowercased().contains(lowercaseQuery) })
        }
    }
    
    func searchTasksByTag(_ tag: String) -> [DomeTask] {
        let tasks = storageService.loadDomeTasks()
        return tasks.filter { $0.tags.contains(tag) }
    }
    
    private func scheduleTaskReminder(_ task: DomeTask, at date: Date) {
        let identifier = "task_reminder_\(task.id.uuidString)"
        
        notificationService.scheduleNotification(
            identifier: identifier,
            title: "Task Due: \(task.title)",
            body: task.notes ?? "Don't forget this task!",
            date: date
        )
    }
    
    // DOME_TASK_SERVICE_END
}

