//
//  RecordingService.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import AVFoundation
import Foundation

protocol RecordingServicing {
    func startRecording() async throws
    func stopRecording() async throws -> AudioBuffer
    func cancelRecording() async
}

nonisolated enum RecordingServiceError: Error, Equatable {
    case permissionDenied
    case recordingUnavailable
    case alreadyRecording
    case notRecording
    case startFailed
}

#if os(iOS)
final class RecordingService: NSObject, RecordingServicing {
    private let importService: any AudioImportServicing
    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    init(
        importService: any AudioImportServicing = AudioImportService(),
        fileManager: FileManager = .default
    ) {
        self.importService = importService
        self.fileManager = fileManager
    }

    func startRecording() async throws {
        guard recorder == nil else {
            throw RecordingServiceError.alreadyRecording
        }

        guard await requestRecordPermission() else {
            throw RecordingServiceError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try session.setActive(true)

        let url = temporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.prepareToRecord()

        guard newRecorder.record() else {
            try? session.setActive(false)
            try? fileManager.removeItem(at: url)
            throw RecordingServiceError.startFailed
        }

        recordingURL = url
        recorder = newRecorder
    }

    func stopRecording() async throws -> AudioBuffer {
        guard let recorder, let recordingURL else {
            throw RecordingServiceError.notRecording
        }

        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false)

        defer {
            try? fileManager.removeItem(at: recordingURL)
        }

        return try await importService.importAudio(from: recordingURL)
    }

    func cancelRecording() async {
        recorder?.stop()

        if let recordingURL {
            try? fileManager.removeItem(at: recordingURL)
        }

        recorder = nil
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func requestRecordPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func temporaryRecordingURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
    }
}
#else
struct RecordingService: RecordingServicing {
    init(importService: any AudioImportServicing = AudioImportService()) {}

    func startRecording() async throws {
        throw RecordingServiceError.recordingUnavailable
    }

    func stopRecording() async throws -> AudioBuffer {
        throw RecordingServiceError.notRecording
    }

    func cancelRecording() async {}
}
#endif
