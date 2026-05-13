//
//  AudioImportRecordingTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import AVFoundation
import XCTest
@testable import Deep_Fried_Audio_Player

private typealias ProjectAudioBuffer = Deep_Fried_Audio_Player.AudioBuffer

final class AudioImportRecordingTests: XCTestCase {
    func testAudioImportServiceDecodesTemporaryPCMFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try makeTemporaryAudioFile(at: url)

        let buffer = try await AudioImportService().importAudio(from: url)

        XCTAssertEqual(buffer.sampleRate, 8_000)
        XCTAssertEqual(buffer.channelCount, 2)
        XCTAssertEqual(buffer.frames, 80)
        XCTAssertEqual(buffer.samples.count, 2)
        XCTAssertTrue(buffer.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(buffer.samples.flatMap { $0 }.map(abs).max() ?? 0, 0.05)
    }

    @MainActor
    func testImportAudioLoadsOriginalAndDoesNotStartPlayback() async throws {
        let buffer = try makeTestBuffer()
        let project = AudioProjectViewModel(
            audioImportService: FakeAudioImportService(result: .success(buffer)),
            recordingService: FakeRecordingService()
        )

        await project.importAudio(from: URL(fileURLWithPath: "/tmp/input.wav"))
        await project.renderSingleModulePreview()

        XCTAssertEqual(project.originalAudioBuffer, buffer)
        XCTAssertNotNil(project.processedPreviewBuffer)
        XCTAssertEqual(project.audioSourceStatusKey, "audio.imported")
        XCTAssertEqual(project.processingState, .ready)
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertFalse(project.isRecording)
    }

    @MainActor
    func testImportFailureSurfacesStatusAndDoesNotStartPlayback() async {
        let project = AudioProjectViewModel(
            audioImportService: FakeAudioImportService(result: .failure(AudioImportServiceError.unreadableFile)),
            recordingService: FakeRecordingService()
        )

        await project.importAudio(from: URL(fileURLWithPath: "/tmp/bad.wav"))

        XCTAssertNil(project.originalAudioBuffer)
        XCTAssertNil(project.processedPreviewBuffer)
        XCTAssertEqual(project.audioSourceStatusKey, "audio.importFailed")
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertFalse(project.isRecording)

        if case .failed = project.processingState {
            // Expected.
        } else {
            XCTFail("Expected failed processing state after import failure.")
        }
    }

    @MainActor
    func testPermissionDeniedSurfacesRecordingStatus() async throws {
        let original = try makeTestBuffer()
        let project = AudioProjectViewModel(
            audioImportService: FakeAudioImportService(result: .success(original)),
            recordingService: FakeRecordingService(startResult: .failure(RecordingServiceError.permissionDenied))
        )
        project.generateSampleAudio()

        await project.startRecording()

        XCTAssertFalse(project.isRecording)
        XCTAssertEqual(project.audioSourceStatusKey, "audio.recordPermissionDenied")
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertNotNil(project.originalAudioBuffer)
    }

    @MainActor
    func testStoppingRecordingLoadsRecordedAudioAndDoesNotStartPlayback() async throws {
        let recordedBuffer = try makeTestBuffer(sampleRate: 16_000, frameCount: 32)
        let recordingService = FakeRecordingService(
            startResult: .success(()),
            stopResult: .success(recordedBuffer)
        )
        let project = AudioProjectViewModel(
            audioImportService: FakeAudioImportService(result: .failure(AudioImportServiceError.unreadableFile)),
            recordingService: recordingService
        )

        await project.startRecording()
        XCTAssertTrue(project.isRecording)
        XCTAssertEqual(project.audioSourceStatusKey, "audio.recording")

        await project.stopRecording()
        await project.renderSingleModulePreview()

        XCTAssertEqual(project.originalAudioBuffer, recordedBuffer)
        XCTAssertEqual(project.audioSourceStatusKey, "audio.recorded")
        XCTAssertFalse(project.isRecording)
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertEqual(project.processingState, .ready)
    }

    private func makeTemporaryAudioFile(at url: URL) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 8_000,
                channels: 2,
                interleaved: false
            )
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 80
            )
        )
        buffer.frameLength = 80

        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for frameIndex in 0..<Int(buffer.frameLength) {
            let time = Float(frameIndex) / 8_000
            channelData[0][frameIndex] = sin(2 * Float.pi * 220 * time) * 0.5
            channelData[1][frameIndex] = sin(2 * Float.pi * 440 * time) * 0.35
        }

        try file.write(from: buffer)
    }

    private func makeTestBuffer(
        sampleRate: Double = 8_000,
        frameCount: Int = 16
    ) throws -> ProjectAudioBuffer {
        let left = (0..<frameCount).map { frameIndex in
            Float(frameIndex) / Float(frameCount)
        }
        let right = left.map { -$0 }

        return try ProjectAudioBuffer(
            sampleRate: sampleRate,
            channelCount: 2,
            samples: [left, right]
        )
    }
}

private struct FakeAudioImportService: AudioImportServicing {
    let result: Result<ProjectAudioBuffer, Error>

    func importAudio(from url: URL) async throws -> ProjectAudioBuffer {
        try result.get()
    }
}

private final class FakeRecordingService: RecordingServicing {
    private let startResult: Result<Void, Error>
    private let stopResult: Result<ProjectAudioBuffer, Error>

    init(
        startResult: Result<Void, Error> = .success(()),
        stopResult: Result<ProjectAudioBuffer, Error> = .failure(RecordingServiceError.notRecording)
    ) {
        self.startResult = startResult
        self.stopResult = stopResult
    }

    func startRecording() async throws {
        try startResult.get()
    }

    func stopRecording() async throws -> ProjectAudioBuffer {
        try stopResult.get()
    }

    func cancelRecording() async {}
}
