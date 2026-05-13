//
//  ExpandedEffectProcessors.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Accelerate
import Foundation

nonisolated struct FilterEQProcessor: ProgressReportingEffectProcessor {
    let type: EffectType = .filterEQ

    func process(
        _ input: AudioBuffer,
        block: EffectBlock,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> AudioBuffer {
        let modeValue = try block.choiceParameter(
            EffectParameterKey.mode,
            default: FilterEQMode.lowPass.rawValue
        )
        let mode = FilterEQMode(rawValue: modeValue) ?? .lowPass
        let mix = Float(
            try block.doubleParameter(EffectParameterKey.mix, default: 1.0)
                .clamped(to: 0.0...1.0)
        )

        guard mix > 0 else {
            progress(EffectProcessorProgress(fractionCompleted: 1))
            return input
        }

        var reporter = EffectProgressReporter(totalUnitCount: try progressUnitCount(for: mode, input: input, block: block))
        var completedUnitCount = 0
        reporter.reportStarted(progress: progress)

        let processedSamples: [[Float]] = switch mode {
        case .lowPass:
            try processLowPass(
                input,
                block: block,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        case .highPass:
            try processHighPass(
                input,
                block: block,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        case .bandPass:
            try processBandPass(
                input,
                block: block,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        case .notch:
            try processNotch(
                input,
                block: block,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        case .randomFrequencyResponse:
            try processRandomFrequencyResponse(
                input,
                block: block,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        }
        reporter.finish(progress: progress)

        return try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: blend(dry: input.samples, wet: processedSamples, mix: mix)
        )
    }

    private func processLowPass(
        _ input: AudioBuffer,
        block: EffectBlock,
        completedUnitCount: inout Int,
        reporter: inout EffectProgressReporter,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> [[Float]] {
        let cutoff = try clampedFrequency(
            block.doubleParameter(EffectParameterKey.cutoff, default: 3_200),
            sampleRate: input.sampleRate
        )
        let resonance = try qValue(from: block)
        let passCount = try slopePassCount(from: block)
        let coefficients = BiquadCoefficients.lowPass(
            sampleRate: input.sampleRate,
            cutoff: cutoff,
            q: resonance
        )

        return input.samples.map {
            apply(
                coefficients,
                to: $0,
                passCount: passCount,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        }
    }

    private func processHighPass(
        _ input: AudioBuffer,
        block: EffectBlock,
        completedUnitCount: inout Int,
        reporter: inout EffectProgressReporter,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> [[Float]] {
        let cutoff = try clampedFrequency(
            block.doubleParameter(EffectParameterKey.cutoff, default: 3_200),
            sampleRate: input.sampleRate
        )
        let resonance = try qValue(from: block)
        let passCount = try slopePassCount(from: block)
        let coefficients = BiquadCoefficients.highPass(
            sampleRate: input.sampleRate,
            cutoff: cutoff,
            q: resonance
        )

        return input.samples.map {
            apply(
                coefficients,
                to: $0,
                passCount: passCount,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        }
    }

    private func processBandPass(
        _ input: AudioBuffer,
        block: EffectBlock,
        completedUnitCount: inout Int,
        reporter: inout EffectProgressReporter,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> [[Float]] {
        let lowCut = try clampedFrequency(
            block.doubleParameter(EffectParameterKey.lowCut, default: 300),
            sampleRate: input.sampleRate
        )
        let highCut = try clampedFrequency(
            block.doubleParameter(EffectParameterKey.highCut, default: 3_400),
            sampleRate: input.sampleRate
        )
        let sortedLowCut = min(lowCut, highCut * 0.8)
        let sortedHighCut = max(highCut, sortedLowCut * 1.25)
            .clamped(to: sortedLowCut...input.sampleRate * 0.49)
        let resonance = try qValue(from: block)
        let passCount = try slopePassCount(from: block)
        let highPass = BiquadCoefficients.highPass(
            sampleRate: input.sampleRate,
            cutoff: sortedLowCut,
            q: resonance
        )
        let lowPass = BiquadCoefficients.lowPass(
            sampleRate: input.sampleRate,
            cutoff: sortedHighCut,
            q: resonance
        )

        return input.samples.map {
            let highPassed = apply(
                highPass,
                to: $0,
                passCount: passCount,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
            return apply(
                lowPass,
                to: highPassed,
                passCount: passCount,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        }
    }

    private func processNotch(
        _ input: AudioBuffer,
        block: EffectBlock,
        completedUnitCount: inout Int,
        reporter: inout EffectProgressReporter,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> [[Float]] {
        let center = try clampedFrequency(
            block.doubleParameter(EffectParameterKey.centerFrequency, default: 1_000),
            sampleRate: input.sampleRate
        )
        let width = try block.doubleParameter(EffectParameterKey.width, default: 1.0)
            .clamped(to: 0.05...4.0)
        let resonance = try qValue(from: block)
        let depth = Float(
            try block.doubleParameter(EffectParameterKey.depth, default: 1.0)
                .clamped(to: 0.0...1.0)
        )
        let passCount = try slopePassCount(from: block)
        let q = (resonance / width).clamped(to: 0.1...50.0)
        let coefficients = BiquadCoefficients.notch(
            sampleRate: input.sampleRate,
            centerFrequency: center,
            q: q
        )
        let notched = input.samples.map {
            apply(
                coefficients,
                to: $0,
                passCount: passCount,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        }

        return blend(dry: input.samples, wet: notched, mix: depth)
    }

    private func processRandomFrequencyResponse(
        _ input: AudioBuffer,
        block: EffectBlock,
        completedUnitCount: inout Int,
        reporter: inout EffectProgressReporter,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> [[Float]] {
        let bandCount = try block.intParameter(EffectParameterKey.bandCount, default: 8)
            .clamped(to: 2...48)
        let frequencyRange = try block.rangeParameter(
            EffectParameterKey.frequencyRange,
            default: EffectParameterRangeValue(lowerBound: 120, upperBound: 12_000)
        )
        let gainRange = try block.rangeParameter(
            EffectParameterKey.gainRange,
            default: EffectParameterRangeValue(lowerBound: -10, upperBound: 10)
        )
        let seed = try block.intParameter(EffectParameterKey.seed, default: 1_337)
        let resonance = try qValue(from: block)
        let passCount = try slopePassCount(from: block)
        let intensity = try block.doubleParameter(EffectParameterKey.intensity, default: 1.0)
            .clamped(to: 0.0...1.0)
        let lowFrequency = try clampedFrequency(
            min(frequencyRange.lowerBound, frequencyRange.upperBound),
            sampleRate: input.sampleRate
        )
        let highFrequency = try clampedFrequency(
            max(frequencyRange.lowerBound, frequencyRange.upperBound),
            sampleRate: input.sampleRate
        )
        let safeHighFrequency = max(highFrequency, lowFrequency * 1.1)
            .clamped(to: lowFrequency...input.sampleRate * 0.49)
        let safeLowFrequency = min(lowFrequency, safeHighFrequency / 1.1)
        let lowGain = min(gainRange.lowerBound, gainRange.upperBound) * intensity
        let highGain = max(gainRange.lowerBound, gainRange.upperBound) * intensity
        var generator = SeededGenerator(seed: UInt64(bitPattern: Int64(seed)))
        let centers = logSpacedFrequencies(
            low: safeLowFrequency,
            high: safeHighFrequency,
            count: bandCount
        )
        let filters = centers.map { center in
            BiquadCoefficients.peakingEQ(
                sampleRate: input.sampleRate,
                centerFrequency: center,
                q: resonance,
                gainDB: generator.nextDouble(in: lowGain...highGain)
            )
        }

        return input.samples.map { channelSamples in
            var output = channelSamples

            for coefficients in filters {
                output = apply(
                    coefficients,
                    to: output,
                    passCount: passCount,
                    completedUnitCount: &completedUnitCount,
                    reporter: &reporter,
                    progress: progress
                )
            }

            return output
        }
    }

    private func progressUnitCount(
        for mode: FilterEQMode,
        input: AudioBuffer,
        block: EffectBlock
    ) throws -> Int {
        let baseUnitCount = processedSampleUnitCount(for: input)
        let passCount = try slopePassCount(from: block)

        switch mode {
        case .lowPass, .highPass, .notch:
            return baseUnitCount * passCount
        case .bandPass:
            return baseUnitCount * passCount * 2
        case .randomFrequencyResponse:
            let bandCount = try block.intParameter(EffectParameterKey.bandCount, default: 8)
                .clamped(to: 2...48)
            return baseUnitCount * passCount * bandCount
        }
    }

    private func qValue(from block: EffectBlock) throws -> Double {
        try block.doubleParameter(EffectParameterKey.resonance, default: 0.85)
            .clamped(to: 0.1...50.0)
    }

    private func slopePassCount(from block: EffectBlock) throws -> Int {
        let slope = try block.doubleParameter(EffectParameterKey.slope, default: 12)
        return slope >= 24 ? 2 : 1
    }

    private func clampedFrequency(_ frequency: Double, sampleRate: Double) throws -> Double {
        guard frequency.isFinite else {
            throw EffectProcessorError.invalidParameter(
                key: "frequency",
                expected: "a finite frequency"
            )
        }

        return frequency.clamped(to: 20.0...(sampleRate * 0.49))
    }

    private func apply(
        _ coefficients: BiquadCoefficients,
        to samples: [Float],
        passCount: Int,
        completedUnitCount: inout Int,
        reporter: inout EffectProgressReporter,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) -> [Float] {
        var output = samples

        for _ in 0..<max(1, passCount) {
            var filter = BiquadFilter(coefficients: coefficients)
            var nextOutput: [Float] = []
            nextOutput.reserveCapacity(output.count)

            for sample in output {
                nextOutput.append(filter.process(sample))
                completedUnitCount += 1
                reporter.reportCompletedUnitCount(completedUnitCount, progress: progress)
            }

            output = nextOutput
        }

        return output
    }
}

nonisolated struct CompressorProcessor: ProgressReportingEffectProcessor {
    let type: EffectType = .compressor

    func process(
        _ input: AudioBuffer,
        block: EffectBlock,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> AudioBuffer {
        let thresholdDB = try block.doubleParameter(EffectParameterKey.threshold, default: -18.0)
            .clamped(to: -80.0...0.0)
        let ratio = try block.doubleParameter(EffectParameterKey.ratio, default: 8.0)
            .clamped(to: 1.0...40.0)
        let attackMS = try block.doubleParameter(EffectParameterKey.attack, default: 5.0)
            .clamped(to: 0.1...1_000.0)
        let releaseMS = try block.doubleParameter(EffectParameterKey.release, default: 80.0)
            .clamped(to: 1.0...5_000.0)
        let inputGain = Float(
            try block.doubleParameter(EffectParameterKey.inputGain, default: 1.0)
                .clamped(to: 0.0...100.0)
        )
        let makeupGain = Float(
            try block.doubleParameter(EffectParameterKey.makeupGain, default: 1.4)
                .clamped(to: 0.0...100.0)
        )
        let mix = Float(
            try block.doubleParameter(EffectParameterKey.mix, default: 1.0)
                .clamped(to: 0.0...1.0)
        )

        var reporter = EffectProgressReporter(totalUnitCount: processedSampleUnitCount(for: input))
        var completedUnitCount = 0
        reporter.reportStarted(progress: progress)

        let attackCoefficient = smoothingCoefficient(milliseconds: attackMS, sampleRate: input.sampleRate)
        let releaseCoefficient = smoothingCoefficient(milliseconds: releaseMS, sampleRate: input.sampleRate)
        let processedSamples = input.samples.map { channelSamples in
            compress(
                channelSamples,
                thresholdDB: Float(thresholdDB),
                ratio: Float(ratio),
                attackCoefficient: attackCoefficient,
                releaseCoefficient: releaseCoefficient,
                inputGain: inputGain,
                makeupGain: makeupGain,
                mix: mix,
                completedUnitCount: &completedUnitCount,
                reporter: &reporter,
                progress: progress
            )
        }
        reporter.finish(progress: progress)

        return try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: processedSamples
        )
    }

    private func compress(
        _ samples: [Float],
        thresholdDB: Float,
        ratio: Float,
        attackCoefficient: Float,
        releaseCoefficient: Float,
        inputGain: Float,
        makeupGain: Float,
        mix: Float,
        completedUnitCount: inout Int,
        reporter: inout EffectProgressReporter,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) -> [Float] {
        var envelope = Float.zero
        var output: [Float] = []
        output.reserveCapacity(samples.count)

        for dry in samples {
            let driven = dry * inputGain
            let level = abs(driven)
            let coefficient = level > envelope ? attackCoefficient : releaseCoefficient
            envelope = coefficient * envelope + (1 - coefficient) * level

            let envelopeDB = amplitudeToDB(envelope)
            let gainDB: Float
            if envelopeDB > thresholdDB {
                let compressedDB = thresholdDB + ((envelopeDB - thresholdDB) / ratio)
                gainDB = compressedDB - envelopeDB
            } else {
                gainDB = 0
            }

            let gain = pow(10, gainDB / 20)
            let wet = driven * gain * makeupGain
            output.append((dry * (1 - mix)) + (wet * mix))
            completedUnitCount += 1
            reporter.reportCompletedUnitCount(completedUnitCount, progress: progress)
        }

        return output
    }

    private func smoothingCoefficient(milliseconds: Double, sampleRate: Double) -> Float {
        let seconds = max(0.000_1, milliseconds / 1_000)
        return Float(exp(-1.0 / (seconds * sampleRate)))
    }

    private func amplitudeToDB(_ amplitude: Float) -> Float {
        20 * log10(max(amplitude, 0.000_000_1))
    }
}

nonisolated struct SpectralDamageProcessor: ProgressReportingEffectProcessor {
    let type: EffectType = .spectralDamage

    func process(
        _ input: AudioBuffer,
        block: EffectBlock,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
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
            progress(EffectProcessorProgress(fractionCompleted: 1))
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
            progress(EffectProcessorProgress(fractionCompleted: 1))
            return input
        }
        defer {
            vDSP_DFT_DestroySetup(forwardSetup)
            vDSP_DFT_DestroySetup(inverseSetup)
        }

        let hopSize = max(1, Int((Double(powerOfTwoWindowSize) * (1.0 - overlap)).rounded()))
        var reporter = EffectProgressReporter(
            totalUnitCount: input.samples.reduce(0) { total, channelSamples in
                total + spectralWindowCount(
                    sampleCount: channelSamples.count,
                    windowSize: powerOfTwoWindowSize,
                    hopSize: hopSize
                )
            }
        )
        var completedWindowCount = 0
        var wetSamples: [[Float]] = []
        wetSamples.reserveCapacity(input.samples.count)
        reporter.reportStarted(progress: progress)

        for channelSamples in input.samples {
            wetSamples.append(
                keepTopKFrequencyBins(
                    channelSamples,
                    sampleRate: input.sampleRate,
                    windowSize: powerOfTwoWindowSize,
                    hopSize: hopSize,
                    componentCount: componentCount,
                    minFrequency: minFrequency,
                    maxFrequency: maxFrequency,
                    forwardSetup: forwardSetup,
                    inverseSetup: inverseSetup,
                    completedWindowCount: &completedWindowCount,
                    reporter: &reporter,
                    progress: progress
                )
            )
        }
        reporter.finish(progress: progress)

        return try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: blend(dry: input.samples, wet: wetSamples, mix: mix)
        )
    }

    private func keepTopKFrequencyBins(
        _ samples: [Float],
        sampleRate: Double,
        windowSize: Int,
        hopSize: Int,
        componentCount: Int,
        minFrequency: Double,
        maxFrequency: Double,
        forwardSetup: vDSP_DFT_Setup,
        inverseSetup: vDSP_DFT_Setup,
        completedWindowCount: inout Int,
        reporter: inout EffectProgressReporter,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
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

            keepTopComponents(
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

            completedWindowCount += 1
            reporter.reportCompletedUnitCount(completedWindowCount, progress: progress)

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

    private func spectralWindowCount(sampleCount: Int, windowSize: Int, hopSize: Int) -> Int {
        guard sampleCount > 0 else {
            return 0
        }

        var count = 0
        var start = 0

        repeat {
            count += 1

            if start + windowSize >= sampleCount {
                break
            }

            start += hopSize
        } while start < sampleCount

        return count
    }

    private func keepTopComponents(
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
}

private nonisolated struct BiquadCoefficients {
    let b0: Float
    let b1: Float
    let b2: Float
    let a1: Float
    let a2: Float

    static func lowPass(sampleRate: Double, cutoff: Double, q: Double) -> BiquadCoefficients {
        make(sampleRate: sampleRate, frequency: cutoff, q: q) { cosW0, alpha, _, a0 in
            (
                b0: (1 - cosW0) / 2 / a0,
                b1: (1 - cosW0) / a0,
                b2: (1 - cosW0) / 2 / a0,
                a1: (-2 * cosW0) / a0,
                a2: (1 - alpha) / a0
            )
        }
    }

    static func highPass(sampleRate: Double, cutoff: Double, q: Double) -> BiquadCoefficients {
        make(sampleRate: sampleRate, frequency: cutoff, q: q) { cosW0, alpha, _, a0 in
            (
                b0: (1 + cosW0) / 2 / a0,
                b1: -(1 + cosW0) / a0,
                b2: (1 + cosW0) / 2 / a0,
                a1: (-2 * cosW0) / a0,
                a2: (1 - alpha) / a0
            )
        }
    }

    static func notch(sampleRate: Double, centerFrequency: Double, q: Double) -> BiquadCoefficients {
        make(sampleRate: sampleRate, frequency: centerFrequency, q: q) { cosW0, alpha, _, a0 in
            (
                b0: 1 / a0,
                b1: (-2 * cosW0) / a0,
                b2: 1 / a0,
                a1: (-2 * cosW0) / a0,
                a2: (1 - alpha) / a0
            )
        }
    }

    static func peakingEQ(
        sampleRate: Double,
        centerFrequency: Double,
        q: Double,
        gainDB: Double
    ) -> BiquadCoefficients {
        let gain = pow(10, gainDB / 40)
        return make(sampleRate: sampleRate, frequency: centerFrequency, q: q) { cosW0, alpha, _, _ in
            let a0 = 1 + (alpha / gain)
            return (
                b0: (1 + (alpha * gain)) / a0,
                b1: (-2 * cosW0) / a0,
                b2: (1 - (alpha * gain)) / a0,
                a1: (-2 * cosW0) / a0,
                a2: (1 - (alpha / gain)) / a0
            )
        }
    }

    private static func make(
        sampleRate: Double,
        frequency: Double,
        q: Double,
        coefficients: (
            _ cosW0: Double,
            _ alpha: Double,
            _ sinW0: Double,
            _ a0: Double
        ) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double)
    ) -> BiquadCoefficients {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2 * q)
        let a0 = 1 + alpha
        let raw = coefficients(cosW0, alpha, sinW0, a0)

        return BiquadCoefficients(
            b0: Float(raw.b0),
            b1: Float(raw.b1),
            b2: Float(raw.b2),
            a1: Float(raw.a1),
            a2: Float(raw.a2)
        )
    }
}

private nonisolated struct BiquadFilter {
    let coefficients: BiquadCoefficients
    private var z1 = Float.zero
    private var z2 = Float.zero

    init(coefficients: BiquadCoefficients) {
        self.coefficients = coefficients
    }

    mutating func process(_ sample: Float) -> Float {
        let output = (coefficients.b0 * sample) + z1
        z1 = (coefficients.b1 * sample) - (coefficients.a1 * output) + z2
        z2 = (coefficients.b2 * sample) - (coefficients.a2 * output)
        return output
    }
}

private nonisolated struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xA5A5_A5A5_A5A5_A5A5 : seed
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        state = (state &* 6_364_136_223_846_793_005) &+ 1_442_695_040_888_963_407
        let unitValue = Double(state >> 11) / Double(UInt64.max >> 11)
        return range.lowerBound + ((range.upperBound - range.lowerBound) * unitValue)
    }
}

private nonisolated func blend(
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

private nonisolated func logSpacedFrequencies(
    low: Double,
    high: Double,
    count: Int
) -> [Double] {
    guard count > 1 else {
        return [low]
    }

    let logLow = log(max(1, low))
    let logHigh = log(max(logLow + 0.001, high))

    return (0..<count).map { index in
        let position = Double(index) / Double(count - 1)
        return exp(logLow + ((logHigh - logLow) * position))
    }
}
