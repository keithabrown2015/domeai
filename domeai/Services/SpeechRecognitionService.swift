//
//  SpeechRecognitionService.swift
//  domeai
//
//  Created by Keith Brown on 11/2/25.
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class SpeechRecognitionService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var errorMessage: String?
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    override init() {
        super.init()
        requestAuthorization()
    }
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.errorMessage = nil
                case .denied, .restricted, .notDetermined:
                    self?.errorMessage = "Speech recognition permission denied"
                @unknown default:
                    self?.errorMessage = "Unknown speech recognition authorization status"
                }
            }
        }
    }
    
    func startRecording() async {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is not available"
            return
        }
        
        // Cancel previous task if it exists
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
            return
        }
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            errorMessage = "Failed to create audio engine"
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Failed to create recognition request"
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            recognizedText = ""
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            return
        }
        
        // TODO: Integrate with AI service for real-time transcription processing
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                }
                
                if let error = error {
                    self.stopRecording()
                    self.errorMessage = error.localizedDescription
                } else if result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        
        isRecording = false
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to deactivate audio session: \(error.localizedDescription)"
        }
    }
}

