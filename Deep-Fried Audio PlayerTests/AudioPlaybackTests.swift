//
//  AudioPlaybackTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import AVFoundation
import XCTest
@testable import Deep_Fried_Audio_Player

private typealias ProjectAudioBuffer = Deep_Fried_Audio_Player.AudioBuffer

final class AudioPlaybackTests: XCTestCase {
    func testPCMBufferConversionPreservesShapeAndSamples() throws {
        let buffer = try ProjectAudioBuffer(
            sampleRate: 8_000,
            channelCount: 2,
            samples: [
                [0.0, 0.25, -0.5],
                [1.0, -1.0, 0.5],
            ]
        )

        let pcmBuffer = try AudioBufferPCMBridge.makePCMBuffer(from: buffer)

        XCTAssertEqual(pcmBuffer.format.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(pcmBuffer.format.isInterleaved)
        XCTAssertEqual(pcmBuffer.format.sampleRate, 8_000)
        XCTAssertEqual(Int(pcmBuffer.format.channelCount), 2)
        XCTAssertEqual(Int(pcmBuffer.frameLength), 3)

        let channelData = try XCTUnwrap(pcmBuffer.floatChannelData)
        for channelIndex in 0..<buffer.channelCount {
            for frameIndex in 0..<buffer.frames {
                XCTAssertEqual(
                    channelData[channelIndex][frameIndex],
                    buffer.samples[channelIndex][frameIndex],
                    accuracy: 0.000_001
                )
            }
        }
    }

    @MainActor
    func testPlayingOriginalAudioUpdatesStateAndCompletesWithoutRealPlayback() async throws {
        let playbackController = FakePlaybackController()
        let project = AudioProjectViewModel(playbackController: playbackController)
        project.generateSampleAudio()
        let originalBuffer = try XCTUnwrap(project.originalAudioBuffer)

        await project.playOriginalAudio()

        XCTAssertEqual(playbackController.playedBuffers, [originalBuffer])
        XCTAssertEqual(project.playbackState, .playingOriginal)
        XCTAssertEqual(project.playbackStatusKey, "playback.playingOriginal")
        XCTAssertEqual(project.operationProgress?.kind, .playback)

        playbackController.completeLatestPlayback()

        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertNil(project.playbackStatusKey)
        XCTAssertNil(project.operationProgress)
    }

    @MainActor
    func testPlayingProcessedAudioUsesProcessedPreview() async throws {
        let playbackController = FakePlaybackController()
        let project = AudioProjectViewModel(playbackController: playbackController)
        project.generateSampleAudio()
        await project.renderSingleModulePreview()
        let processedBuffer = try XCTUnwrap(project.processedPreviewBuffer)

        await project.playProcessedAudio()

        XCTAssertEqual(playbackController.playedBuffers, [processedBuffer])
        XCTAssertEqual(project.playbackState, .playingProcessed)
        XCTAssertEqual(project.playbackStatusKey, "playback.playingProcessed")
    }

    @MainActor
    func testStopPlaybackStopsControllerAndClearsState() async {
        let playbackController = FakePlaybackController()
        let project = AudioProjectViewModel(playbackController: playbackController)
        project.generateSampleAudio()
        await project.playOriginalAudio()
        let stopCountBeforeManualStop = playbackController.stopCallCount
        XCTAssertEqual(project.operationProgress?.kind, .playback)

        project.stopPlayback()

        XCTAssertEqual(playbackController.stopCallCount, stopCountBeforeManualStop + 1)
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertNil(project.playbackStatusKey)
        XCTAssertNil(project.operationProgress)
    }

    @MainActor
    func testPlaybackFailureReturnsToStoppedStateAndShowsStatus() async {
        let playbackController = FakePlaybackController(playResult: .failure(FakePlaybackError.failed))
        let project = AudioProjectViewModel(playbackController: playbackController)
        project.generateSampleAudio()

        await project.playOriginalAudio()

        XCTAssertTrue(playbackController.playedBuffers.isEmpty)
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertEqual(project.playbackStatusKey, "playback.failed")
    }

    @MainActor
    func testMissingPlaybackBuffersShowRecoverableStatus() async {
        let playbackController = FakePlaybackController()
        let project = AudioProjectViewModel(playbackController: playbackController)

        await project.playOriginalAudio()

        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertEqual(project.playbackStatusKey, "playback.noOriginal")
        XCTAssertTrue(playbackController.playedBuffers.isEmpty)

        project.generateSampleAudio()
        await project.playProcessedAudio()

        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertEqual(project.playbackStatusKey, "playback.noProcessed")
        XCTAssertTrue(playbackController.playedBuffers.isEmpty)
    }

    @MainActor
    func testGeneratingSampleAudioStopsExistingPlaybackWithoutAutoplay() {
        let playbackController = FakePlaybackController()
        let project = AudioProjectViewModel(playbackController: playbackController)
        project.playbackState = .playingProcessed
        project.playbackStatusKey = "playback.playingProcessed"

        project.generateSampleAudio()

        XCTAssertEqual(playbackController.stopCallCount, 1)
        XCTAssertTrue(playbackController.playedBuffers.isEmpty)
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertNil(project.playbackStatusKey)
        XCTAssertNotNil(project.originalAudioBuffer)
    }

    @MainActor
    func testImportAudioStopsExistingPlaybackWithoutAutoplay() async throws {
        let importedBuffer = try makeTestBuffer()
        let playbackController = FakePlaybackController()
        let project = AudioProjectViewModel(
            audioImportService: FakeAudioImportService(result: .success(importedBuffer)),
            recordingService: FakeRecordingService(),
            playbackController: playbackController
        )
        project.playbackState = .playingOriginal
        project.playbackStatusKey = "playback.playingOriginal"

        await project.importAudio(from: URL(fileURLWithPath: "/tmp/input.wav"))

        XCTAssertEqual(playbackController.stopCallCount, 1)
        XCTAssertTrue(playbackController.playedBuffers.isEmpty)
        XCTAssertEqual(project.originalAudioBuffer, importedBuffer)
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertNil(project.playbackStatusKey)
    }

    @MainActor
    func testStartRecordingStopsExistingPlaybackWithoutAutoplay() async {
        let playbackController = FakePlaybackController()
        let project = AudioProjectViewModel(
            recordingService: FakeRecordingService(startResult: .success(())),
            playbackController: playbackController
        )
        project.playbackState = .playingProcessed
        project.playbackStatusKey = "playback.playingProcessed"

        await project.startRecording()

        XCTAssertEqual(playbackController.stopCallCount, 1)
        XCTAssertTrue(playbackController.playedBuffers.isEmpty)
        XCTAssertTrue(project.isRecording)
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertNil(project.playbackStatusKey)
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

private enum FakePlaybackError: Error {
    case failed
}

@MainActor
private final class FakePlaybackController: AudioPlaybackControlling {
    private let playResult: Result<Void, Error>
    private var completions: [@MainActor () -> Void] = []
    var playedBuffers: [ProjectAudioBuffer] = []
    var stopCallCount = 0

    init(playResult: Result<Void, Error> = .success(())) {
        self.playResult = playResult
    }

    func play(
        _ buffer: ProjectAudioBuffer,
        completion: @escaping @MainActor () -> Void
    ) async throws {
        try playResult.get()
        playedBuffers.append(buffer)
        completions.append(completion)
    }

    func stop() {
        stopCallCount += 1
    }

    func completeLatestPlayback() {
        completions.last?()
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

    init(startResult: Result<Void, Error> = .success(())) {
        self.startResult = startResult
    }

    func startRecording() async throws {
        try startResult.get()
    }

    func stopRecording() async throws -> ProjectAudioBuffer {
        throw RecordingServiceError.notRecording
    }

    func cancelRecording() async {}
}
