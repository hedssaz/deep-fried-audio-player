//
//  CodecCapabilityTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import XCTest
@testable import Deep_Fried_Audio_Player

final class CodecCapabilityTests: XCTestCase {
    func testUnavailableCodecsAreNotRepresentedAsAvailableRoundTrips() {
        let catalog = CodecCapabilityCatalog.current
        let unavailableIDs: [CodecID] = [.amrNB, .speex, .g711, .g729]

        for id in unavailableIDs {
            let capability = catalog.capability(for: id)

            XCTAssertNotNil(capability, "Missing codec capability for \(id.rawValue).")
            XCTAssertNotEqual(capability?.status, .available)
            XCTAssertFalse(capability?.supportsRoundTrip ?? true)
        }
    }

    func testDefaultCodecParametersOnlyExposeAvailableRoundTripChoices() {
        let catalog = CodecCapabilityCatalog.current
        let availableIDs = Set(catalog.availableRoundTripCapabilities.map(\.id.rawValue))
        let unavailableIDs = Set([CodecID.amrNB, .speex, .g711, .g729].map(\.rawValue))

        for type in [EffectType.bitrateReduction, .lowQualityCodec] {
            let block = EffectBlock.defaultBlock(type: type, order: 0)

            if availableIDs.isEmpty {
                XCTAssertTrue(block.parameters.isEmpty)
                continue
            }

            let codecParameter = block.parameters.first {
                $0.key == EffectParameterKey.codec
            }
            let bitRateParameter = block.parameters.first {
                $0.key == EffectParameterKey.bitRateKbps
            }
            let exposedChoiceIDs = Set(codecParameter?.choices.map(\.value) ?? [])

            XCTAssertEqual(exposedChoiceIDs, availableIDs)
            XCTAssertTrue(exposedChoiceIDs.isDisjoint(with: unavailableIDs))
            XCTAssertNotNil(bitRateParameter)
        }
    }

    func testOnlyLowQualityCodecIsUserFacingWhenCodecRoundTripIsAvailable() {
        let expectedTypes: [EffectType] = CodecCapabilityCatalog.current.hasAvailableRoundTripCodec
            ? [.lowQualityCodec]
            : []

        XCTAssertEqual(EffectType.userFacingCodecEffectTypes, expectedTypes)
    }

    func testBuiltInRegistryContainsCodecProcessors() {
        XCTAssertNotNil(EffectProcessorRegistry.builtIn.processor(for: .bitrateReduction))
        XCTAssertNotNil(EffectProcessorRegistry.builtIn.processor(for: .lowQualityCodec))
    }

    func testCodecRoundTripProcessorUsesRealEncodeDecodeWhenAvailable() throws {
        let catalog = CodecCapabilityCatalog.current

        guard let capability = catalog.availableRoundTripCapabilities.first else {
            throw XCTSkip("No AVFoundation codec round-trip is available in this environment.")
        }

        let processor = try XCTUnwrap(
            EffectProcessorRegistry.builtIn.processor(for: .lowQualityCodec)
        )
        var block = EffectBlock.defaultBlock(type: .lowQualityCodec, order: 0)
        try setParameter(
            &block,
            key: EffectParameterKey.codec,
            value: .choice(capability.id.rawValue)
        )

        if let bitRateKbps = capability.defaultBitRateKbps {
            try setParameter(
                &block,
                key: EffectParameterKey.bitRateKbps,
                value: .int(bitRateKbps)
            )
        }

        let input = try SampleAudioFactory.makeDevelopmentSample(
            duration: 0.12,
            sampleRate: 44_100,
            channelCount: 1
        )
        let output = try processor.process(input, block: block)

        XCTAssertGreaterThan(output.frames, 0)
        XCTAssertGreaterThan(output.channelCount, 0)
        XCTAssertTrue(output.sampleRate.isFinite)
        XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertTrue(
            output.frames != input.frames
                || output.samples != input.samples
                || capability.id == .appleLossless
        )
    }

    func testDefaultCodecBlocksRenderDevelopmentSampleWhenAvailable() throws {
        let catalog = CodecCapabilityCatalog.current

        guard catalog.hasAvailableRoundTripCodec else {
            throw XCTSkip("No AVFoundation codec round-trip is available in this environment.")
        }

        let input = try SampleAudioFactory.makeDevelopmentSample(
            duration: 0.2,
            sampleRate: 44_100,
            channelCount: 2
        )

        for type in [EffectType.lowQualityCodec, .bitrateReduction] {
            let processor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: type))
            let block = EffectBlock.defaultBlock(type: type, order: 0)
            let output = try processor.process(input, block: block)

            XCTAssertGreaterThan(output.frames, 0)
            XCTAssertGreaterThan(output.channelCount, 0)
            XCTAssertTrue(output.sampleRate.isFinite)
            XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        }
    }

    private func setParameter(
        _ block: inout EffectBlock,
        key: String,
        value: EffectParameterValue,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let index = try XCTUnwrap(
            block.parameters.firstIndex { $0.key == key },
            "Missing parameter \(key).",
            file: file,
            line: line
        )

        block.parameters[index].value = value
    }
}
