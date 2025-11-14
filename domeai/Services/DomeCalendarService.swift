//
//  DomeCalendarService.swift
//  domeai
//
//  Dome's internal calendar service - manages all calendar events
//

import Foundation

class DomeCalendarService {
    static let shared = DomeCalendarService()
    
    private let storageService = StorageService.shared
    private let notificationService = NotificationService.shared
    
    private init() {}
    
    // DOME_CALENDAR_SERVICE_START
    
    func createEvent(_ event: DomeEvent) {
        var events = storageService.loadDomeEvents()
        events.append(event)
        storageService.saveDomeEvents(events)
        
        if let reminderMinutes = event.reminderMinutesBefore {
            scheduleEventReminder(event, minutesBefore: reminderMinutes)
        }
        
        print("✅ Created Dome calendar event: \(event.title)")
    }
    
    func updateEvent(_ updatedEvent: DomeEvent) {
        var events = storageService.loadDomeEvents()
        if let index = events.firstIndex(where: { $0.id == updatedEvent.id }) {
            events[index] = updatedEvent
            storageService.saveDomeEvents(events)
            
            if let oldIdentifier = updatedEvent.notificationIdentifier {
                notificationService.cancelNotification(identifier: oldIdentifier)
            }
            if let reminderMinutes = updatedEvent.reminderMinutesBefore {
                scheduleEventReminder(updatedEvent, minutesBefore: reminderMinutes)
            }
            
            print("✅ Updated Dome calendar event: \(updatedEvent.title)")
        }
    }
    
    func deleteEvent(_ event: DomeEvent) {
        var events = storageService.loadDomeEvents()
        events.removeAll { $0.id == event.id }
        storageService.saveDomeEvents(events)
        
        if let identifier = event.notificationIdentifier {
            notificationService.cancelNotification(identifier: identifier)
        }
        
        print("✅ Deleted Dome calendar event: \(event.title)")
    }
    
    func getEvents(for date: Date) -> [DomeEvent] {
        let events = storageService.loadDomeEvents()
        let calendar = Calendar.current
        return events.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: date)
        }
    }
    
    func getUpcomingEvents(limit: Int = 10) -> [DomeEvent] {
        let events = storageService.loadDomeEvents()
        let now = Date()
        return events
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { $0 }
    }
    
    func searchEvents(query: String) -> [DomeEvent] {
        let events = storageService.loadDomeEvents()
        let lowercaseQuery = query.lowercased()
        return events.filter { event in
            event.title.lowercased().contains(lowercaseQuery) ||
            (event.notes?.lowercased().contains(lowercaseQuery) ?? false) ||
            event.tags.contains(where: { $0.lowercased().contains(lowercaseQuery) })
        }
    }
    
    func searchEventsByTag(_ tag: String) -> [DomeEvent] {
        let events = storageService.loadDomeEvents()
        return events.filter { $0.tags.contains(tag) }
    }
    
    private func scheduleEventReminder(_ event: DomeEvent, minutesBefore: Int) {
        let reminderDate = event.startDate.addingTimeInterval(-Double(minutesBefore * 60))
        let identifier = "event_reminder_\(event.id.uuidString)"
        
        notificationService.scheduleNotification(
            identifier: identifier,
            title: "Upcoming: \(event.title)",
            body: event.notes ?? "Event starts in \(minutesBefore) minutes",
            date: reminderDate
        )
    }
    
    // DOME_CALENDAR_SERVICE_END
}

