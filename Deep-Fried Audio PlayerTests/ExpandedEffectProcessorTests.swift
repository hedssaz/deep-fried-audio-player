//
//  ExpandedEffectProcessorTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import XCTest
@testable import Deep_Fried_Audio_Player

final class ExpandedEffectProcessorTests: XCTestCase {
    func testFilterEQVisibleParametersFollowSelectedMode() {
        var block = EffectBlock.defaultBlock(type: .filterEQ, order: 0)

        XCTAssertEqual(block.filterEQMode, .lowPass)
        XCTAssertTrue(block.visibleParameters.contains { $0.key == EffectParameterKey.cutoff })
        XCTAssertFalse(block.visibleParameters.contains { $0.key == EffectParameterKey.lowCut })
        XCTAssertFalse(block.visibleParameters.contains { $0.key == EffectParameterKey.gainRange })

        setParameter(&block, key: EffectParameterKey.mode, value: .choice(FilterEQMode.bandPass.rawValue))

        XCTAssertEqual(block.filterEQMode, .bandPass)
        XCTAssertTrue(block.visibleParameters.contains { $0.key == EffectParameterKey.lowCut })
        XCTAssertTrue(block.visibleParameters.contains { $0.key == EffectParameterKey.highCut })
        XCTAssertFalse(block.visibleParameters.contains { $0.key == EffectParameterKey.cutoff })

        setParameter(
            &block,
            key: EffectParameterKey.mode,
            value: .choice(FilterEQMode.randomFrequencyResponse.rawValue)
        )

        XCTAssertEqual(block.filterEQMode, .randomFrequencyResponse)
        XCTAssertTrue(block.visibleParameters.contains { $0.key == EffectParameterKey.bandCount })
        XCTAssertTrue(block.visibleParameters.contains { $0.key == EffectParameterKey.frequencyRange })
        XCTAssertTrue(block.visibleParameters.contains { $0.key == EffectParameterKey.gainRange })
        XCTAssertTrue(block.visibleParameters.contains { $0.key == EffectParameterKey.seed })
    }

    func testFilterEQModesPreserveShapeAndReturnFiniteChangedSamples() throws {
        let input = try SampleAudioFactory.makeDevelopmentSample(duration: 0.05)
        let processor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: .filterEQ))

        for mode in FilterEQMode.allCases {
            var block = EffectBlock.defaultBlock(type: .filterEQ, order: 0)
            setParameter(&block, key: EffectParameterKey.mode, value: .choice(mode.rawValue))

            let output = try processor.process(input, block: block)

            XCTAssertEqual(output.sampleRate, input.sampleRate)
            XCTAssertEqual(output.channelCount, input.channelCount)
            XCTAssertEqual(output.frames, input.frames)
            XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
            XCTAssertNotEqual(output.samples, input.samples, "\(mode.rawValue) should change the signal.")
        }
    }

    func testRandomFrequencyResponseIsDeterministicAndChangesWithSeed() throws {
        let input = try SampleAudioFactory.makeDevelopmentSample(duration: 0.05)
        let processor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: .filterEQ))
        var firstBlock = randomFrequencyResponseBlock(seed: 123)
        let secondBlock = randomFrequencyResponseBlock(seed: 123)
        let thirdBlock = randomFrequencyResponseBlock(seed: 456)

        let firstOutput = try processor.process(input, block: firstBlock)
        let secondOutput = try processor.process(input, block: secondBlock)
        let thirdOutput = try processor.process(input, block: thirdBlock)

        XCTAssertEqual(firstOutput.samples, secondOutput.samples)
        XCTAssertNotEqual(firstOutput.samples, thirdOutput.samples)
        setParameter(&firstBlock, key: EffectParameterKey.intensity, value: .float(0.25))
        let lowerIntensityOutput = try processor.process(input, block: firstBlock)
        XCTAssertNotEqual(firstOutput.samples, lowerIntensityOutput.samples)
    }

    func testCompressorReducesDynamicRangeForQuietAndLoudSections() throws {
        let quiet = Array(repeating: Float(0.08), count: 256)
        let loud = (0..<256).map { index in
            index.isMultiple(of: 2) ? Float(0.9) : Float(-0.9)
        }
        let input = try AudioBuffer(
            sampleRate: 44_100,
            channelCount: 1,
            samples: [quiet + loud]
        )
        var block = EffectBlock.defaultBlock(type: .compressor, order: 0)
        setParameter(&block, key: EffectParameterKey.threshold, value: .float(-24))
        setParameter(&block, key: EffectParameterKey.ratio, value: .float(12))
        setParameter(&block, key: EffectParameterKey.attack, value: .float(0.1))
        setParameter(&block, key: EffectParameterKey.release, value: .float(60))
        setParameter(&block, key: EffectParameterKey.makeupGain, value: .float(1.0))

        let processor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: .compressor))
        let output = try processor.process(input, block: block)
        let dryRatio = peak(Array(input.samples[0][256..<512])) / peak(Array(input.samples[0][0..<256]))
        let wetRatio = peak(Array(output.samples[0][256..<512])) / peak(Array(output.samples[0][0..<256]))

        XCTAssertEqual(output.frames, input.frames)
        XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertLessThan(wetRatio, dryRatio)
    }

    func testSpectralDamageTopKPreservesShapeAndChangesWithComponentCount() throws {
        let input = try makeMultiToneBuffer()
        let processor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: .spectralDamage))
        var sparseBlock = EffectBlock.defaultBlock(type: .spectralDamage, order: 0)
        var denserBlock = sparseBlock
        setParameter(&sparseBlock, key: EffectParameterKey.componentCount, value: .int(2))
        setParameter(&denserBlock, key: EffectParameterKey.componentCount, value: .int(24))
        setParameter(&sparseBlock, key: EffectParameterKey.windowSize, value: .choice("512"))
        setParameter(&denserBlock, key: EffectParameterKey.windowSize, value: .choice("512"))

        let sparseOutput = try processor.process(input, block: sparseBlock)
        let denserOutput = try processor.process(input, block: denserBlock)

        XCTAssertEqual(sparseOutput.sampleRate, input.sampleRate)
        XCTAssertEqual(sparseOutput.channelCount, input.channelCount)
        XCTAssertEqual(sparseOutput.frames, input.frames)
        XCTAssertTrue(sparseOutput.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertTrue(denserOutput.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertNotEqual(sparseOutput.samples, input.samples)
        XCTAssertNotEqual(sparseOutput.samples, denserOutput.samples)
    }

    func testExpandedEffectProgressReportingMatchesPlainOutputForRepresentativeBlocks() throws {
        let input = try makeMultiToneBuffer()
        var spectralBlock = EffectBlock.defaultBlock(type: .spectralDamage, order: 0)
        setParameter(&spectralBlock, key: EffectParameterKey.windowSize, value: .choice("512"))

        let cases: [(EffectType, EffectBlock)] = [
            (.filterEQ, randomFrequencyResponseBlock(seed: 123)),
            (.compressor, EffectBlock.defaultBlock(type: .compressor, order: 0)),
            (.spectralDamage, spectralBlock),
        ]

        for (type, block) in cases {
            let processor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: type))
            let progressProcessor = try XCTUnwrap(processor as? any ProgressReportingEffectProcessor)
            let progressLog = ExpandedEffectProgressLog()

            let plainOutput = try processor.process(input, block: block)
            let progressOutput = try progressProcessor.process(input, block: block) { progress in
                progressLog.append(progress.fractionCompleted)
            }

            XCTAssertEqual(progressOutput, plainOutput, "\(type.rawValue) changed output while reporting progress.")
            XCTAssertEqual(progressLog.values().last ?? -1, 1.0, accuracy: 0.000_001)
        }
    }

    func testSpectralDamageReportsIntermediateWindowProgressAndCompletes() throws {
        let input = try makeMultiToneBuffer()
        let baseProcessor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: .spectralDamage))
        let processor = try XCTUnwrap(baseProcessor as? any ProgressReportingEffectProcessor)
        var block = EffectBlock.defaultBlock(type: .spectralDamage, order: 0)
        setParameter(&block, key: EffectParameterKey.windowSize, value: .choice("512"))
        let progressLog = ExpandedEffectProgressLog()

        _ = try processor.process(input, block: block) { progress in
            progressLog.append(progress.fractionCompleted)
        }

        let values = progressLog.values()
        XCTAssertTrue(values.contains { $0 > 0 && $0 < 1 })
        XCTAssertEqual(values.last ?? -1, 1.0, accuracy: 0.000_001)
    }

    @MainActor
    func testAvailableModuleListsExposeUnifiedFilterEQAndHideLegacyFilters() {
        let project = AudioProjectViewModel()

        XCTAssertTrue(project.availableSingleModuleTypes.contains(.filterEQ))
        XCTAssertTrue(project.availableWorkflowModuleTypes.contains(.filterEQ))
        XCTAssertTrue(project.availableSingleModuleTypes.contains(.compressor))
        XCTAssertTrue(project.availableWorkflowModuleTypes.contains(.spectralDamage))

        let shouldExposeCodecModules = CodecCapabilityCatalog.current.hasAvailableRoundTripCodec
        XCTAssertEqual(
            project.availableSingleModuleTypes.contains(.bitrateReduction),
            false
        )
        XCTAssertEqual(
            project.availableWorkflowModuleTypes.contains(.lowQualityCodec),
            shouldExposeCodecModules
        )

        for legacyType in EffectType.legacyIndividualFilterTypes {
            XCTAssertFalse(project.availableSingleModuleTypes.contains(legacyType))
            XCTAssertFalse(project.availableWorkflowModuleTypes.contains(legacyType))
        }
    }

    private func randomFrequencyResponseBlock(seed: Int) -> EffectBlock {
        var block = EffectBlock.defaultBlock(type: .filterEQ, order: 0)
        setParameter(&block, key: EffectParameterKey.mode, value: .choice(FilterEQMode.randomFrequencyResponse.rawValue))
        setParameter(&block, key: EffectParameterKey.seed, value: .int(seed))
        return block
    }

    private func setParameter(
        _ block: inout EffectBlock,
        key: String,
        value: EffectParameterValue
    ) {
        guard let index = block.parameters.firstIndex(where: { $0.key == key }) else {
            XCTFail("Missing parameter \(key).")
            return
        }

        block.parameters[index].value = value
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.map(abs).max() ?? 0
    }

    private func makeMultiToneBuffer() throws -> AudioBuffer {
        let sampleRate = 44_100.0
        let frames = 2_048
        let frequencies = [120.0, 440.0, 1_300.0, 3_200.0, 6_400.0, 9_000.0]
        let samples = (0..<frames).map { frameIndex in
            let time = Double(frameIndex) / sampleRate
            let value = frequencies.enumerated().reduce(0.0) { partial, element in
                let amplitude = 0.12 / Double(element.offset + 1)
                return partial + (sin(2 * Double.pi * element.element * time) * amplitude)
            }

            return Float(value)
        }

        return try AudioBuffer(
            sampleRate: sampleRate,
            channelCount: 1,
            samples: [samples]
        )
    }
}

private final class ExpandedEffectProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var progressValues: [Double] = []

    func append(_ value: Double) {
        lock.withLock {
            progressValues.append(value)
        }
    }

    func values() -> [Double] {
        lock.withLock {
            progressValues
        }
    }
}
