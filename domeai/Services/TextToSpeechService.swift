//
//  TextToSpeechService.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import AVFoundation
import Combine

class TextToSpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = TextToSpeechService()
    
    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false
    
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(_ text: String) {
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        
        // Try to find best male English voice
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let maleVoices = voices.filter { 
            $0.language.starts(with: "en") && 
            ($0.name.contains("Male") || 
             $0.identifier.contains("Aaron") ||
             $0.identifier.contains("Fred") ||
             $0.identifier.contains("Daniel"))
        }
        
        // Use first available male voice, or default
        if let maleVoice = maleVoices.first {
            utterance.voice = maleVoice
            print("🗣️ Using voice: \(maleVoice.name)")
        } else {
            // Fallback to any en-US voice
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        utterance.rate = 0.52  // Natural pace
        utterance.pitchMultiplier = 0.9  // Slightly lower pitch for male voice
        utterance.volume = 1.0
        
        currentUtterance = utterance
        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false
    }
    
    // Legacy method name for compatibility
    func speak(text: String) {
        speak(text)
    }
    
    func pause() {
        if synthesizer.isSpeaking && !isPaused {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
        }
    }
    
    func resume() {
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        }
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
    }
    
    // Delegate methods
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = true
            self?.isPaused = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.isPaused = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.isPaused = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = false
        }
    }
}
