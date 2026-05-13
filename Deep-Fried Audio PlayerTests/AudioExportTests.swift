//
//  AudioExportTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/14.
//

import AVFoundation
import XCTest
@testable import Deep_Fried_Audio_Player

private typealias AppAudioBuffer = Deep_Fried_Audio_Player.AudioBuffer

final class AudioExportTests: XCTestCase {
    @MainActor
    func testWAVExportWritesDecodableAudio() async throws {
        let input = try SampleAudioFactory.makeDevelopmentSample(
            duration: 0.05,
            sampleRate: 16_000,
            channelCount: 2
        )
        let data = try await AudioExportService().export(input, format: .wav)
        let output = try decode(data: data, extension: "wav")

        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(output.sampleRate, input.sampleRate)
        XCTAssertEqual(output.channelCount, input.channelCount)
        XCTAssertGreaterThan(output.frames, 0)
        XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
    }

    @MainActor
    func testMP3ExportIsUnavailableWhenCodecCapabilityIsUnavailable() async throws {
        let service = AudioExportService(codecCatalog: CodecCapabilityCatalog(capabilities: [
            CodecCapability(
                id: .mp3,
                status: .unavailable,
                audioFormatID: kAudioFormatMPEGLayer3,
                fileExtension: "mp3",
                defaultBitRateKbps: 64,
                bitRateRange: CodecBitRateRange(minKbps: 64, maxKbps: 320),
                unavailableReasonKey: "codec.reason.unavailableOnDevice"
            ),
        ]))
        let input = try SampleAudioFactory.makeDevelopmentSample(duration: 0.05)

        XCTAssertFalse(service.isFormatAvailable(.mp3))

        do {
            _ = try await service.export(input, format: .mp3)
            XCTFail("Expected MP3 export to be unavailable.")
        } catch AudioExportServiceError.formatUnavailable(.mp3) {
            // Expected.
        }
    }

    @MainActor
    func testMP3ExportWritesDecodableAudioWhenAvailable() async throws {
        let service = AudioExportService()
        guard service.isFormatAvailable(.mp3) else {
            throw XCTSkip("MP3 export is unavailable in this environment.")
        }

        let input = try SampleAudioFactory.makeDevelopmentSample(
            duration: 0.08,
            sampleRate: 44_100,
            channelCount: 1
        )
        let data = try await service.export(input, format: .mp3)
        let output = try decode(data: data, extension: "mp3")

        XCTAssertFalse(data.isEmpty)
        XCTAssertGreaterThan(output.frames, 0)
        XCTAssertGreaterThan(output.channelCount, 0)
        XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
    }

    func testEmptyAudioExportThrowsExportError() async throws {
        let empty = try AppAudioBuffer(sampleRate: 44_100, channelCount: 1, samples: [[]])

        do {
            _ = try await AudioExportService().export(empty, format: .wav)
            XCTFail("Expected empty audio export to fail.")
        } catch AudioExportServiceError.emptyAudio {
            // Expected.
        }
    }

    @MainActor
    func testPreparingProcessedWAVExportReturnsDocumentPayload() async throws {
        let exportedData = Data([0x44, 0x46, 0x41, 0x50])
        let exportService = FakeAudioExportService(
            availableFormats: [.wav],
            exportData: exportedData
        )
        let project = AudioProjectViewModel(audioExportService: exportService)
        project.processedPreviewBuffer = try SampleAudioFactory.makeDevelopmentSample(duration: 0.05)

        let export = await project.prepareProcessedExport(
            format: .wav,
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let preparedExport = try XCTUnwrap(export)
        XCTAssertEqual(preparedExport.format, .wav)
        XCTAssertEqual(preparedExport.document.data, exportedData)
        XCTAssertTrue(preparedExport.defaultFileName.hasPrefix("deep-fried-processed-"))
        XCTAssertTrue(preparedExport.defaultFileName.hasSuffix(".wav"))
        XCTAssertNil(project.exportStatusKey)
        XCTAssertEqual(exportService.exportCallCount, 1)
    }

    @MainActor
    func testPreparingExportWithoutProcessedPreviewReportsStatus() async {
        let exportService = FakeAudioExportService(
            availableFormats: [.wav],
            exportData: Data([0x01])
        )
        let project = AudioProjectViewModel(audioExportService: exportService)

        let export = await project.prepareProcessedExport(format: .wav)

        XCTAssertNil(export)
        XCTAssertEqual(project.exportStatusKey, "export.noProcessed")
        XCTAssertEqual(exportService.exportCallCount, 0)
    }

    @MainActor
    func testPreparingUnavailableMP3ExportReportsStatusWithoutExporting() async throws {
        let exportService = FakeAudioExportService(
            availableFormats: [.wav],
            exportData: Data([0x01])
        )
        let project = AudioProjectViewModel(audioExportService: exportService)
        project.processedPreviewBuffer = try SampleAudioFactory.makeDevelopmentSample(duration: 0.05)

        let export = await project.prepareProcessedExport(format: .mp3)

        XCTAssertNil(export)
        XCTAssertFalse(project.isMP3ExportAvailable)
        XCTAssertEqual(project.exportStatusKey, "export.mp3Unavailable")
        XCTAssertEqual(exportService.exportCallCount, 0)
    }

    @MainActor
    func testExportAvailabilityRequiresProcessedPreviewAndNoRecording() async throws {
        let project = AudioProjectViewModel(
            audioExportService: FakeAudioExportService(
                availableFormats: [.wav],
                exportData: Data([0x01])
            ),
            recordingService: FakeExportRecordingService()
        )

        XCTAssertFalse(project.canExportProcessedAudio)

        project.processedPreviewBuffer = try SampleAudioFactory.makeDevelopmentSample(duration: 0.05)
        XCTAssertTrue(project.canExportProcessedAudio)

        await project.startRecording()
        XCTAssertFalse(project.canExportProcessedAudio)
    }

    private func decode(data: Data, extension fileExtension: String) throws -> AppAudioBuffer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try data.write(to: url)
        return try AudioFileDecoder.decodeAudioFile(at: url)
    }
}

private final class FakeAudioExportService: AudioExportServicing, @unchecked Sendable {
    private let availableFormats: Set<AudioExportFormat>
    private let exportData: Data
    private(set) var exportCallCount = 0

    init(
        availableFormats: Set<AudioExportFormat>,
        exportData: Data
    ) {
        self.availableFormats = availableFormats
        self.exportData = exportData
    }

    func isFormatAvailable(_ format: AudioExportFormat) -> Bool {
        availableFormats.contains(format)
    }

    func export(_ buffer: AppAudioBuffer, format: AudioExportFormat) async throws -> Data {
        exportCallCount += 1
        return exportData
    }
}

private final class FakeExportRecordingService: RecordingServicing {
    func startRecording() async throws {}

    func stopRecording() async throws -> AppAudioBuffer {
        try SampleAudioFactory.makeDevelopmentSample(duration: 0.05)
    }

    func cancelRecording() async {}
}
