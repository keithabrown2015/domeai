//
//  UserSettings.swift
//  domeai
//
//  Created for DomeAI email feature
//

import Foundation
import Combine

class UserSettings: ObservableObject {
    @Published var email: String? {
        didSet {
            saveEmail()
        }
    }
    
    private let emailKey = "userEmail"
    
    init() {
        loadEmail()
    }
    
    private func loadEmail() {
        if let savedEmail = UserDefaults.standard.string(forKey: emailKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !savedEmail.isEmpty {
            email = savedEmail
        } else {
            email = nil
        }
    }
    
    private func saveEmail() {
        // IMPORTANT: DO NOT assign to `email` here to avoid recursion.
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: emailKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: emailKey)
        }
    }
    
    func setEmail(_ newEmail: String?) {
        let trimmed = newEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        email = trimmed.isEmpty ? nil : trimmed
    }
}

