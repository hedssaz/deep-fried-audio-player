//
//  SampleAudioFactory.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

enum SampleAudioFactoryError: Error, Equatable {
    case invalidDuration
    case invalidSampleRate
    case invalidChannelCount
}

struct SampleAudioFactory {
    static func makeDevelopmentSample(
        duration: TimeInterval = 2.0,
        sampleRate: Double = 44_100,
        channelCount: Int = 2
    ) throws -> AudioBuffer {
        guard duration.isFinite, duration > 0 else {
            throw SampleAudioFactoryError.invalidDuration
        }

        guard sampleRate.isFinite, sampleRate > 0 else {
            throw SampleAudioFactoryError.invalidSampleRate
        }

        guard channelCount > 0 else {
            throw SampleAudioFactoryError.invalidChannelCount
        }

        let frameCount = max(1, Int((duration * sampleRate).rounded(.toNearestOrAwayFromZero)))
        let fadeFrameCount = max(1, Int((sampleRate * 0.015).rounded(.toNearestOrAwayFromZero)))
        let twoPi = 2.0 * Double.pi
        var samples = Array(repeating: [Float](), count: channelCount)

        for channelIndex in samples.indices {
            samples[channelIndex].reserveCapacity(frameCount)
        }

        for frameIndex in 0..<frameCount {
            let time = Double(frameIndex) / sampleRate
            let position = time / duration
            let fadeIn = min(1.0, Double(frameIndex) / Double(fadeFrameCount))
            let fadeOut = min(1.0, Double(frameCount - frameIndex - 1) / Double(fadeFrameCount))
            let envelope = max(0.0, min(fadeIn, fadeOut))
            let sweepFrequency = 240.0 + (2_600.0 * position)

            for channelIndex in 0..<channelCount {
                let phase = Double(channelIndex) * Double.pi / 3.0
                let stereoSkew = 1.0 + (Double(channelIndex) * 0.035)
                let fundamental = sin(twoPi * 110.0 * stereoSkew * time + phase) * 0.28
                let mid = sin(twoPi * 440.0 * time + phase * 0.5) * 0.18
                let sweep = sin(twoPi * sweepFrequency * time) * 0.16
                let high = sin(twoPi * 6_400.0 * time + phase) * 0.07
                let pulse = sin(twoPi * 7.0 * time) > 0.88 ? 0.08 : 0.0
                let value = (fundamental + mid + sweep + high + pulse) * envelope

                samples[channelIndex].append(Float(max(-0.95, min(0.95, value))))
            }
        }

        return try AudioBuffer(
            sampleRate: sampleRate,
            channelCount: channelCount,
            frames: frameCount,
            samples: samples
        )
    }
}
