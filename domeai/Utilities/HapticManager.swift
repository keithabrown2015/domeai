//
//  HapticManager.swift
//  domeai
//
//  Created by Keith Brown on 11/8/25.
//

import UIKit

/// Centralized haptic feedback helper to keep vibration usage consistent and lightweight.
final class HapticManager {
    static let shared = HapticManager()
    
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    private init() {
        prepareGenerators()
    }
    
    private func prepareGenerators() {
        impactGenerator.prepare()
        mediumImpactGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }
    
    /// Trigger an impact feedback with the desired style.
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// Trigger a notification feedback (success, warning, error).
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
    }
    
    /// Trigger a selection change feedback.
    func selection() {
        selectionGenerator.selectionChanged()
    }
}

