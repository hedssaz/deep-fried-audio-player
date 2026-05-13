//
//  ExpandedEffectProcessorTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import Accelerate
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

    func testSpectralDamageFFTMatchesDFTReferenceAcrossParameterCombinations() throws {
        let input = try makeMultiToneBuffer()
        let processor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: .spectralDamage))
        let frequencyRanges: [(min: Double?, max: Double?)] = [
            (nil, nil),
            (400, 7_500),
        ]

        for componentCount in [2, 12, 24] {
            for windowSize in [256, 512, 1_024] {
                for overlap in [0.0, 0.5, 0.875] {
                    for frequencyRange in frequencyRanges {
                        var block = EffectBlock.defaultBlock(type: .spectralDamage, order: 0)
                        setParameter(&block, key: EffectParameterKey.componentCount, value: .int(componentCount))
                        setParameter(&block, key: EffectParameterKey.windowSize, value: .choice(String(windowSize)))
                        setParameter(&block, key: EffectParameterKey.overlap, value: .float(overlap))

                        if let minFrequency = frequencyRange.min,
                           let maxFrequency = frequencyRange.max {
                            setParameter(&block, key: EffectParameterKey.minFrequency, value: .float(minFrequency))
                            setParameter(&block, key: EffectParameterKey.maxFrequency, value: .float(maxFrequency))
                        }

                        let actual = try processor.process(input, block: block)
                        let expected = try spectralDamageDFTReference(input, block: block)
                        let stats = differenceStats(actual.samples, expected.samples)
                        let minFrequencyDescription = frequencyRange.min.map { String($0) } ?? "default"
                        let maxFrequencyDescription = frequencyRange.max.map { String($0) } ?? "default"
                        let configuration = [
                            "componentCount=\(componentCount)",
                            "windowSize=\(windowSize)",
                            "overlap=\(overlap)",
                            "minFrequency=\(minFrequencyDescription)",
                            "maxFrequency=\(maxFrequencyDescription)",
                        ].joined(separator: ", ")

                        XCTAssertEqual(actual.sampleRate, expected.sampleRate, configuration)
                        XCTAssertEqual(actual.channelCount, expected.channelCount, configuration)
                        XCTAssertEqual(actual.frames, expected.frames, configuration)
                        XCTAssertTrue(actual.samples.flatMap { $0 }.allSatisfy(\.isFinite), configuration)
                        XCTAssertLessThanOrEqual(stats.maxAbs, 0.000_1, configuration)
                        XCTAssertLessThanOrEqual(stats.rms, 0.000_01, configuration)
                    }
                }
            }
        }
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

    private func spectralDamageDFTReference(
        _ input: AudioBuffer,
        block: EffectBlock
    ) throws -> AudioBuffer {
        let modeValue = try block.choiceParameter(
            EffectParameterKey.mode,
            default: SpectralDamageMode.keepTopKFrequencyBins.rawValue
        )
        guard SpectralDamageMode(rawValue: modeValue) == .keepTopKFrequencyBins else {
            throw EffectProcessorError.invalidParameter(
                key: EffectParameterKey.mode,
                expected: SpectralDamageMode.keepTopKFrequencyBins.rawValue
            )
        }

        let componentCount = try block.intParameter(EffectParameterKey.componentCount, default: 12)
            .clamped(to: 1...256)
        let windowSize = try block.intParameter(EffectParameterKey.windowSize, default: 512)
            .clamped(to: 128...2_048)
        let powerOfTwoWindowSize = previousPowerOfTwo(windowSize)
        let overlap = try block.doubleParameter(EffectParameterKey.overlap, default: 0.5)
            .clamped(to: 0.0...0.875)
        let minFrequency = try block.doubleParameter(EffectParameterKey.minFrequency, default: 80.0)
            .clamped(to: 0.0...(input.sampleRate * 0.49))
        let maxFrequency = try block.doubleParameter(EffectParameterKey.maxFrequency, default: 12_000.0)
            .clamped(to: minFrequency...(input.sampleRate * 0.49))
        _ = try block.boolParameter(EffectParameterKey.preservePhase, default: true)
        let mix = Float(
            try block.doubleParameter(EffectParameterKey.mix, default: 1.0)
                .clamped(to: 0.0...1.0)
        )

        guard mix > 0, input.frames > 0 else {
            return input
        }

        guard let forwardSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(powerOfTwoWindowSize),
            vDSP_DFT_Direction.FORWARD
        ),
              let inverseSetup = vDSP_DFT_zop_CreateSetup(
                nil,
                vDSP_Length(powerOfTwoWindowSize),
                vDSP_DFT_Direction.INVERSE
              ) else {
            return input
        }
        defer {
            vDSP_DFT_DestroySetup(forwardSetup)
            vDSP_DFT_DestroySetup(inverseSetup)
        }

        let hopSize = max(1, Int((Double(powerOfTwoWindowSize) * (1.0 - overlap)).rounded()))
        let wetSamples = input.samples.map { channelSamples in
            referenceKeepTopKFrequencyBins(
                channelSamples,
                sampleRate: input.sampleRate,
                windowSize: powerOfTwoWindowSize,
                hopSize: hopSize,
                componentCount: componentCount,
                minFrequency: minFrequency,
                maxFrequency: maxFrequency,
                forwardSetup: forwardSetup,
                inverseSetup: inverseSetup
            )
        }

        return try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: referenceBlend(dry: input.samples, wet: wetSamples, mix: mix)
        )
    }

    private func referenceKeepTopKFrequencyBins(
        _ samples: [Float],
        sampleRate: Double,
        windowSize: Int,
        hopSize: Int,
        componentCount: Int,
        minFrequency: Double,
        maxFrequency: Double,
        forwardSetup: vDSP_DFT_Setup,
        inverseSetup: vDSP_DFT_Setup
    ) -> [Float] {
        let window = hannWindow(size: windowSize)
        var output = [Float](repeating: 0, count: samples.count)
        var weights = [Float](repeating: 0, count: samples.count)
        var start = 0

        repeat {
            var realInput = [Float](repeating: 0, count: windowSize)
            let imaginaryInput = [Float](repeating: 0, count: windowSize)
            var realSpectrum = [Float](repeating: 0, count: windowSize)
            var imaginarySpectrum = [Float](repeating: 0, count: windowSize)

            for frameOffset in 0..<windowSize {
                let sampleIndex = start + frameOffset
                guard sampleIndex < samples.count else {
                    break
                }

                realInput[frameOffset] = samples[sampleIndex] * window[frameOffset]
            }

            vDSP_DFT_Execute(
                forwardSetup,
                realInput,
                imaginaryInput,
                &realSpectrum,
                &imaginarySpectrum
            )

            referenceKeepTopComponents(
                real: &realSpectrum,
                imaginary: &imaginarySpectrum,
                sampleRate: sampleRate,
                windowSize: windowSize,
                componentCount: componentCount,
                minFrequency: minFrequency,
                maxFrequency: maxFrequency
            )

            var realOutput = [Float](repeating: 0, count: windowSize)
            var imaginaryOutput = [Float](repeating: 0, count: windowSize)
            vDSP_DFT_Execute(
                inverseSetup,
                realSpectrum,
                imaginarySpectrum,
                &realOutput,
                &imaginaryOutput
            )

            let normalization = Float(windowSize)
            for frameOffset in 0..<windowSize {
                let sampleIndex = start + frameOffset
                guard sampleIndex < samples.count else {
                    break
                }

                let weightedWindow = window[frameOffset] * window[frameOffset]
                output[sampleIndex] += (realOutput[frameOffset] / normalization) * window[frameOffset]
                weights[sampleIndex] += weightedWindow
            }

            if start + windowSize >= samples.count {
                break
            }

            start += hopSize
        } while start < samples.count

        return output.indices.map { index in
            let weight = weights[index]
            guard weight > 0.000_001 else {
                return samples[index]
            }

            return output[index] / weight
        }
    }

    private func referenceKeepTopComponents(
        real: inout [Float],
        imaginary: inout [Float],
        sampleRate: Double,
        windowSize: Int,
        componentCount: Int,
        minFrequency: Double,
        maxFrequency: Double
    ) {
        let halfWindow = windowSize / 2
        let candidates = (1..<halfWindow).compactMap { bin -> (bin: Int, magnitude: Float)? in
            let frequency = Double(bin) * sampleRate / Double(windowSize)
            guard frequency >= minFrequency, frequency <= maxFrequency else {
                return nil
            }

            let magnitude = hypot(real[bin], imaginary[bin])
            return (bin, magnitude)
        }
        let keptBins = Set(
            candidates
                .sorted { $0.magnitude > $1.magnitude }
                .prefix(componentCount)
                .map(\.bin)
        )

        for bin in 0..<windowSize {
            let mirroredBin = bin == 0 ? 0 : windowSize - bin
            let shouldKeep = keptBins.contains(bin) || keptBins.contains(mirroredBin)

            if !shouldKeep {
                real[bin] = 0
                imaginary[bin] = 0
            }
        }
    }

    private func referenceBlend(
        dry: [[Float]],
        wet: [[Float]],
        mix: Float
    ) -> [[Float]] {
        let clampedMix = mix.clamped(to: 0...1)

        return zip(dry, wet).map { dryChannel, wetChannel in
            zip(dryChannel, wetChannel).map { drySample, wetSample in
                (drySample * (1 - clampedMix)) + (wetSample * clampedMix)
            }
        }
    }

    private func differenceStats(
        _ lhs: [[Float]],
        _ rhs: [[Float]]
    ) -> (maxAbs: Float, rms: Float) {
        var maxAbs = Float.zero
        var sumSquares = Double.zero
        var count = 0

        for (lhsChannel, rhsChannel) in zip(lhs, rhs) {
            for (lhsSample, rhsSample) in zip(lhsChannel, rhsChannel) {
                let difference = lhsSample - rhsSample
                maxAbs = max(maxAbs, abs(difference))
                sumSquares += Double(difference * difference)
                count += 1
            }
        }

        let rms = count > 0 ? Float(sqrt(sumSquares / Double(count))) : 0
        return (maxAbs, rms)
    }

    private func hannWindow(size: Int) -> [Float] {
        guard size > 1 else {
            return [1]
        }

        return (0..<size).map { index in
            Float(0.5 - (0.5 * cos((2.0 * Double.pi * Double(index)) / Double(size - 1))))
        }
    }

    private func previousPowerOfTwo(_ value: Int) -> Int {
        var power = 1

        while power * 2 <= value {
            power *= 2
        }

        return max(128, power)
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
