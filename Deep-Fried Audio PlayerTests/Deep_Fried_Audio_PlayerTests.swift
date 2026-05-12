//
//  Deep_Fried_Audio_PlayerTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by hedssaz on 2026/5/13.
//

import XCTest
@testable import Deep_Fried_Audio_Player

final class Deep_Fried_Audio_PlayerTests: XCTestCase {
    func testAudioBufferCalculatesDurationAndPreservesShape() throws {
        let buffer = try AudioBuffer(
            sampleRate: 44_100,
            channelCount: 2,
            samples: [
                [0.0, 0.5, -0.5],
                [1.0, 0.0, -1.0],
            ]
        )

        XCTAssertEqual(buffer.sampleRate, 44_100)
        XCTAssertEqual(buffer.channelCount, 2)
        XCTAssertEqual(buffer.frames, 3)
        XCTAssertEqual(buffer.duration, 3.0 / 44_100.0, accuracy: 0.000_001)
        XCTAssertTrue(buffer.samples.flatMap { $0 }.allSatisfy { $0.isFinite })
    }

    func testAudioBufferRejectsInvalidInput() {
        XCTAssertAudioBufferThrows(.invalidSampleRate) {
            try AudioBuffer(sampleRate: 0, channelCount: 1, samples: [[0.0]])
        }

        XCTAssertAudioBufferThrows(.invalidChannelCount) {
            try AudioBuffer(sampleRate: 44_100, channelCount: 0, samples: [])
        }

        XCTAssertAudioBufferThrows(.channelCountMismatch(expected: 2, actual: 1)) {
            try AudioBuffer(sampleRate: 44_100, channelCount: 2, samples: [[0.0]])
        }

        XCTAssertAudioBufferThrows(.frameCountMismatch(channel: 0, expected: 2, actual: 1)) {
            try AudioBuffer(sampleRate: 44_100, channelCount: 1, frames: 2, samples: [[0.0]])
        }

        XCTAssertAudioBufferThrows(.nonFiniteSample(channel: 0, frame: 1)) {
            try AudioBuffer(sampleRate: 44_100, channelCount: 1, samples: [[0.0, .nan]])
        }

        XCTAssertAudioBufferThrows(.nonFiniteSample(channel: 0, frame: 1)) {
            try AudioBuffer(sampleRate: 44_100, channelCount: 1, samples: [[0.0, .infinity]])
        }
    }

    func testEffectParametersRoundTripAllKinds() throws {
        let parameters = [
            EffectParameter(
                key: "drive",
                labelKey: "parameter.drive",
                value: .float(0.75),
                valueRange: .float(min: 0.0, max: 1.0),
                unitKey: "unit.percent"
            ),
            EffectParameter(
                key: "bits",
                labelKey: "parameter.bits",
                value: .int(8),
                valueRange: .int(min: 1, max: 16),
                unitKey: "unit.bit"
            ),
            EffectParameter(
                key: "oversampling",
                labelKey: "parameter.oversampling",
                value: .bool(true)
            ),
            EffectParameter(
                key: "codec",
                labelKey: "parameter.codec",
                value: .choice("aac"),
                choices: [
                    EffectParameterChoice(value: "aac", labelKey: "codec.aac"),
                    EffectParameterChoice(value: "mp3", labelKey: "codec.mp3"),
                ]
            ),
            EffectParameter(
                key: "band",
                labelKey: "parameter.band",
                value: .range(EffectParameterRangeValue(lowerBound: 400, upperBound: 2_400)),
                valueRange: .range(min: 20, max: 20_000),
                unitKey: "unit.hz"
            ),
        ]

        let decoded = try roundTrip(parameters)

        XCTAssertEqual(decoded, parameters)
        XCTAssertEqual(decoded.map(\.value.kind), [.float, .int, .bool, .choice, .range])
    }

    func testEffectBlockRoundTripPreservesIdentityAndConfiguration() throws {
        let block = EffectBlock(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            type: .bitDepthReduction,
            name: "effect.bitDepthReduction",
            isEnabled: false,
            order: 3,
            parameters: [
                EffectParameter(
                    key: "bits",
                    labelKey: "parameter.bits",
                    value: .int(6),
                    valueRange: .int(min: 1, max: 16),
                    unitKey: "unit.bit"
                ),
            ],
            presetName: "tiny-speaker"
        )

        let decoded = try roundTrip(block)

        XCTAssertEqual(decoded, block)
        XCTAssertEqual(decoded.id, block.id)
        XCTAssertEqual(decoded.type, .bitDepthReduction)
        XCTAssertEqual(decoded.order, 3)
        XCTAssertEqual(decoded.parameters, block.parameters)
        XCTAssertEqual(decoded.presetName, "tiny-speaker")
    }

    func testWorkflowRoundTripPreservesBlocksAndDates() throws {
        let workflow = Workflow(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "workflow.test",
            blocks: [
                EffectBlock(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    type: .clipping,
                    name: "effect.clipping",
                    order: 0
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_600)
        )

        let decoded = try roundTrip(workflow)

        XCTAssertEqual(decoded, workflow)
        XCTAssertEqual(decoded.blocks.count, 1)
        XCTAssertEqual(decoded.blocks.first?.type, .clipping)
    }

    func testWorkflowOrderedBlocksSortsByOrder() {
        let first = EffectBlock(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            type: .limiter,
            name: "effect.limiter",
            order: 2
        )
        let second = EffectBlock(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            type: .sampleRateReduction,
            name: "effect.sampleRateReduction",
            order: 0
        )
        let third = EffectBlock(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            type: .clipping,
            name: "effect.clipping",
            order: 1
        )
        let workflow = Workflow(name: "workflow.ordering", blocks: [first, second, third])

        XCTAssertEqual(workflow.orderedBlocks.map(\.id), [second.id, third.id, first.id])
    }

    func testSampleAudioFactoryCreatesDeterministicFiniteStereoBuffer() throws {
        let first = try SampleAudioFactory.makeDevelopmentSample(duration: 0.1, sampleRate: 1_000)
        let second = try SampleAudioFactory.makeDevelopmentSample(duration: 0.1, sampleRate: 1_000)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.sampleRate, 1_000)
        XCTAssertEqual(first.channelCount, 2)
        XCTAssertEqual(first.frames, 100)
        XCTAssertEqual(first.samples.count, 2)
        XCTAssertTrue(first.samples.flatMap { $0 }.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(first.samples.flatMap { $0 }.map(abs).max() ?? 0, 0.05)
    }

    func testWaveformDownsamplerReturnsPeakBuckets() throws {
        let buffer = try AudioBuffer(
            sampleRate: 8,
            channelCount: 2,
            samples: [
                [-1.0, -0.25, 0.25, 1.0],
                [0.5, -0.75, 0.75, -0.5],
            ]
        )

        let samples = WaveformDownsampler.downsample(buffer, targetSampleCount: 2)

        XCTAssertEqual(
            samples,
            [
                WaveformSample(index: 0, minimum: -1.0, maximum: 0.5),
                WaveformSample(index: 1, minimum: -0.5, maximum: 1.0),
            ]
        )
    }

    @MainActor
    func testGeneratingSampleAudioRendersPreviewWithoutStartingPlayback() async {
        let project = AudioProjectViewModel()

        project.generateSampleAudio()
        await project.renderSingleModulePreview()

        XCTAssertNotNil(project.originalAudioBuffer)
        XCTAssertNotNil(project.processedPreviewBuffer)
        XCTAssertEqual(project.processingState, .ready)
        XCTAssertEqual(project.playbackState, .stopped)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func XCTAssertAudioBufferThrows(
        _ expectedError: AudioBufferError,
        _ expression: () throws -> AudioBuffer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? AudioBufferError, expectedError, file: file, line: line)
        }
    }
}
