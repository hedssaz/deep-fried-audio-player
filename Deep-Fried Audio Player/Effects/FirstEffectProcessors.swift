//
//  FirstEffectProcessors.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated enum EffectProcessorError: Error, Equatable, CustomStringConvertible {
    case invalidParameter(key: String, expected: String)

    var description: String {
        switch self {
        case let .invalidParameter(key, expected):
            "Invalid parameter '\(key)'; expected \(expected)."
        }
    }
}

extension EffectProcessorRegistry {
    nonisolated static let builtIn = EffectProcessorRegistry(processors: [
        SampleRateReductionProcessor(),
        BitDepthReductionProcessor(),
        ClippingProcessor(),
        FilterEQProcessor(),
        CompressorProcessor(),
        LimiterProcessor(),
        SpectralDamageProcessor(),
        CodecRoundTripProcessor(type: .bitrateReduction),
        CodecRoundTripProcessor(type: .lowQualityCodec),
    ])
}

nonisolated struct SampleRateReductionProcessor: EffectProcessor {
    let type: EffectType = .sampleRateReduction

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        let targetSampleRate = try block.doubleParameter(
            EffectParameterKey.targetSampleRate,
            default: 11_025
        )
        let clampedTarget = targetSampleRate.clamped(to: 1...input.sampleRate)
        let holdFrames = max(1, Int((input.sampleRate / clampedTarget).rounded()))

        guard holdFrames > 1 else {
            return input
        }

        let processedSamples = input.samples.map { channelSamples in
            channelSamples.indices.map { frameIndex in
                channelSamples[(frameIndex / holdFrames) * holdFrames]
            }
        }

        return try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: processedSamples
        )
    }
}

nonisolated struct BitDepthReductionProcessor: EffectProcessor {
    let type: EffectType = .bitDepthReduction

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        let bits = try block.intParameter(EffectParameterKey.bits, default: 6)
            .clamped(to: 1...24)

        let processedSamples = input.samples.map { channelSamples in
            channelSamples.map { sample in
                quantize(sample, bits: bits)
            }
        }

        return try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: processedSamples
        )
    }

    private func quantize(_ sample: Float, bits: Int) -> Float {
        let clampedSample = sample.clamped(to: -1...1)

        guard bits > 1 else {
            return clampedSample >= 0 ? 1 : -1
        }

        let scale = Float((1 << min(bits - 1, 23)) - 1)
        guard scale > 0 else {
            return clampedSample
        }

        return (clampedSample * scale).rounded() / scale
    }
}

nonisolated struct ClippingProcessor: EffectProcessor {
    let type: EffectType = .clipping

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        let drive = Float(
            try block.doubleParameter(EffectParameterKey.drive, default: 2.5)
                .clamped(to: 0...100)
        )
        let threshold = Float(
            try block.doubleParameter(EffectParameterKey.threshold, default: 0.45)
                .clamped(to: 0.001...1)
        )

        let processedSamples = input.samples.map { channelSamples in
            channelSamples.map { sample in
                let driven = sample * drive
                return driven.clamped(to: -threshold...threshold) / threshold
            }
        }

        return try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: processedSamples
        )
    }
}

nonisolated struct LimiterProcessor: EffectProcessor {
    let type: EffectType = .limiter

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        let inputGain = Float(
            try block.doubleParameter(EffectParameterKey.inputGain, default: 3.0)
                .clamped(to: 0...100)
        )
        let ceiling = Float(
            try block.doubleParameter(EffectParameterKey.ceiling, default: 0.92)
                .clamped(to: 0.001...1)
        )

        let processedSamples = input.samples.map { channelSamples in
            channelSamples.map { sample in
                (sample * inputGain).clamped(to: -ceiling...ceiling)
            }
        }

        return try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: processedSamples
        )
    }
}

extension EffectBlock {
    nonisolated func doubleParameter(_ key: String, default defaultValue: Double) throws -> Double {
        guard let value = parameters.first(where: { $0.key == key })?.value else {
            return defaultValue
        }

        let resolvedValue: Double
        switch value {
        case let .float(value):
            resolvedValue = value
        case let .int(value):
            resolvedValue = Double(value)
        case let .choice(value):
            guard let parsedValue = Double(value) else {
                throw EffectProcessorError.invalidParameter(
                    key: key,
                    expected: "a numeric choice"
                )
            }
            resolvedValue = parsedValue
        case .bool, .range:
            throw EffectProcessorError.invalidParameter(
                key: key,
                expected: "a numeric value"
            )
        }

        guard resolvedValue.isFinite else {
            throw EffectProcessorError.invalidParameter(
                key: key,
                expected: "a finite numeric value"
            )
        }

        return resolvedValue
    }

    nonisolated func intParameter(_ key: String, default defaultValue: Int) throws -> Int {
        guard let value = parameters.first(where: { $0.key == key })?.value else {
            return defaultValue
        }

        switch value {
        case let .int(value):
            return value
        case let .float(value):
            guard value.isFinite else {
                throw EffectProcessorError.invalidParameter(
                    key: key,
                    expected: "a finite integer value"
                )
            }
            return Int(value.rounded())
        case let .choice(value):
            guard let parsedValue = Int(value) else {
                throw EffectProcessorError.invalidParameter(
                    key: key,
                    expected: "an integer choice"
                )
            }
            return parsedValue
        case .bool, .range:
            throw EffectProcessorError.invalidParameter(
                key: key,
                expected: "an integer value"
            )
        }
    }

    nonisolated func choiceParameter(_ key: String, default defaultValue: String) throws -> String {
        guard let value = parameters.first(where: { $0.key == key })?.value else {
            return defaultValue
        }

        switch value {
        case let .choice(value):
            return value
        case let .int(value):
            return String(value)
        case let .float(value):
            guard value.isFinite else {
                throw EffectProcessorError.invalidParameter(
                    key: key,
                    expected: "a finite choice value"
                )
            }
            return String(value)
        case .bool, .range:
            throw EffectProcessorError.invalidParameter(
                key: key,
                expected: "a choice value"
            )
        }
    }

    nonisolated func rangeParameter(
        _ key: String,
        default defaultValue: EffectParameterRangeValue
    ) throws -> EffectParameterRangeValue {
        guard let value = parameters.first(where: { $0.key == key })?.value else {
            return defaultValue
        }

        guard case let .range(value) = value,
              value.lowerBound.isFinite,
              value.upperBound.isFinite else {
            throw EffectProcessorError.invalidParameter(
                key: key,
                expected: "a finite range value"
            )
        }

        return value
    }

    nonisolated func boolParameter(_ key: String, default defaultValue: Bool) throws -> Bool {
        guard let value = parameters.first(where: { $0.key == key })?.value else {
            return defaultValue
        }

        guard case let .bool(value) = value else {
            throw EffectProcessorError.invalidParameter(
                key: key,
                expected: "a boolean value"
            )
        }

        return value
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
