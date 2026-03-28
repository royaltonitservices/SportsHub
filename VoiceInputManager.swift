//
//  VoiceInputManager.swift
//  SportsHub
//
//  Voice recognition for AI Coach natural conversation
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class VoiceInputManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var permissionStatus: VoicePermissionStatus = .notDetermined
    
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        checkPermissions()
    }
    
    // MARK: - Permission Handling
    
    func checkPermissions() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioApplication.shared.recordPermission
        
        switch (speechStatus, micStatus) {
        case (.authorized, .granted):
            permissionStatus = .authorized
        case (.denied, _), (_, .denied):
            permissionStatus = .denied
        case (.restricted, _) where speechStatus == .restricted:
            permissionStatus = .restricted
        case (_, _) where speechStatus == .restricted:
            permissionStatus = .restricted
        default:
            permissionStatus = .notDetermined
        }
    }
    
    func requestPermissions() async -> Bool {
        // Request speech recognition permission
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        guard speechGranted else {
            permissionStatus = .denied
            errorMessage = "Voice input requires speech recognition access. Enable it in Settings to talk to your coach."
            return false
        }
        
        // Request microphone permission
        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        guard micGranted else {
            permissionStatus = .denied
            errorMessage = "Microphone access is turned off. Enable it in Settings to talk to your coach."
            return false
        }
        
        permissionStatus = .authorized
        return true
    }
    
    // MARK: - Recording Control
    
    func startRecording() async {
        // Check permissions first
        if permissionStatus != .authorized {
            let granted = await requestPermissions()
            guard granted else { return }
        }
        
        // Reset state
        transcribedText = ""
        errorMessage = nil
        
        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not start voice input. Try again or type instead."
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Voice input is unavailable right now. You can still type your question."
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        // Start audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            errorMessage = "Could not initialize audio. Try again or type instead."
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "We couldn't hear that clearly. Try again or type instead."
            return
        }
        
        // Start recognition
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Voice input is temporarily unavailable. You can still type your message."
            stopRecording()
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let result = result {
                    self.transcribedText = result.bestTranscription.formattedString
                }
                
                if error != nil || result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }
    }
    
    func stopRecording() {
        isRecording = false
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    func cancelRecording() {
        stopRecording()
        transcribedText = ""
        errorMessage = nil
    }
}

// MARK: - Permission Status

enum VoicePermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
    
    var userFacingMessage: String {
        switch self {
        case .notDetermined:
            return "Tap the microphone to talk to your coach"
        case .authorized:
            return "Voice input ready"
        case .denied:
            return "Microphone access is turned off. Enable it in Settings to use voice."
        case .restricted:
            return "Voice input is restricted on this device"
        }
    }
}
