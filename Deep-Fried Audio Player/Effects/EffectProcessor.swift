//
//  EffectProcessor.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated protocol EffectProcessor: Sendable {
    var type: EffectType { get }

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer
}

nonisolated struct EffectProcessorProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case processing
        case codecPreparing
        case codecEncoding
        case codecDecoding
        case codecFinalizing
    }

    let phase: Phase
    let fractionCompleted: Double

    init(
        phase: Phase = .processing,
        fractionCompleted: Double
    ) {
        self.phase = phase
        self.fractionCompleted = fractionCompleted.isFinite
            ? fractionCompleted.clamped(to: 0...1)
            : 0
    }
}

nonisolated protocol ProgressReportingEffectProcessor: EffectProcessor {
    func process(
        _ input: AudioBuffer,
        block: EffectBlock,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> AudioBuffer
}

extension ProgressReportingEffectProcessor {
    nonisolated func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        try process(input, block: block) { _ in }
    }
}

nonisolated struct EffectProgressReporter {
    private let phase: EffectProcessorProgress.Phase
    private let totalUnitCount: Int
    private let minimumFractionStep: Double
    private var lastReportedFraction = -Double.infinity

    init(
        totalUnitCount: Int,
        phase: EffectProcessorProgress.Phase = .processing,
        minimumFractionStep: Double = 0.02
    ) {
        self.phase = phase
        self.totalUnitCount = max(1, totalUnitCount)
        self.minimumFractionStep = max(0, minimumFractionStep)
    }

    mutating func reportStarted(
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) {
        reportFraction(0, force: true, progress: progress)
    }

    mutating func reportCompletedUnitCount(
        _ completedUnitCount: Int,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) {
        let boundedCompletedUnitCount = completedUnitCount.clamped(to: 0...totalUnitCount)
        let fraction = Double(boundedCompletedUnitCount) / Double(totalUnitCount)
        reportFraction(fraction, force: false, progress: progress)
    }

    mutating func finish(
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) {
        reportFraction(1, force: true, progress: progress)
    }

    private mutating func reportFraction(
        _ fraction: Double,
        force: Bool,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) {
        let clampedFraction = fraction.isFinite ? fraction.clamped(to: 0...1) : 0
        guard force
                || clampedFraction >= 1
                || clampedFraction - lastReportedFraction >= minimumFractionStep else {
            return
        }

        lastReportedFraction = max(lastReportedFraction, clampedFraction)
        progress(
            EffectProcessorProgress(
                phase: phase,
                fractionCompleted: lastReportedFraction
            )
        )
    }
}

nonisolated func processedSampleUnitCount(for input: AudioBuffer) -> Int {
    max(1, input.samples.reduce(0) { total, channelSamples in
        total + channelSamples.count
    })
}

nonisolated func mapAudioSamplesWithProgress(
    _ input: AudioBuffer,
    progress: @escaping @Sendable (EffectProcessorProgress) -> Void,
    transform: (Float) -> Float
) -> [[Float]] {
    var reporter = EffectProgressReporter(totalUnitCount: processedSampleUnitCount(for: input))
    var completedUnitCount = 0
    var processedSamples: [[Float]] = []
    processedSamples.reserveCapacity(input.samples.count)
    reporter.reportStarted(progress: progress)

    for channelSamples in input.samples {
        var processedChannel: [Float] = []
        processedChannel.reserveCapacity(channelSamples.count)

        for sample in channelSamples {
            processedChannel.append(transform(sample))
            completedUnitCount += 1
            reporter.reportCompletedUnitCount(completedUnitCount, progress: progress)
        }

        processedSamples.append(processedChannel)
    }

    reporter.finish(progress: progress)
    return processedSamples
}
