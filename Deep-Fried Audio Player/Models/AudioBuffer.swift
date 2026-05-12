//
//  AudioBuffer.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

enum AudioBufferError: Error, Equatable {
    case invalidSampleRate
    case invalidChannelCount
    case channelCountMismatch(expected: Int, actual: Int)
    case invalidFrameCount
    case frameCountMismatch(channel: Int, expected: Int, actual: Int)
    case nonFiniteSample(channel: Int, frame: Int)
}

struct AudioBuffer: Codable, Equatable {
    let sampleRate: Double
    let channelCount: Int
    let frames: Int
    let samples: [[Float]]

    var duration: TimeInterval {
        Double(frames) / sampleRate
    }

    init(
        sampleRate: Double,
        channelCount: Int,
        frames: Int? = nil,
        samples: [[Float]]
    ) throws {
        guard sampleRate.isFinite, sampleRate > 0 else {
            throw AudioBufferError.invalidSampleRate
        }

        guard channelCount > 0 else {
            throw AudioBufferError.invalidChannelCount
        }

        guard samples.count == channelCount else {
            throw AudioBufferError.channelCountMismatch(
                expected: channelCount,
                actual: samples.count
            )
        }

        let resolvedFrames = frames ?? samples.first?.count ?? 0
        guard resolvedFrames >= 0 else {
            throw AudioBufferError.invalidFrameCount
        }

        try Self.validate(samples: samples, expectedFrames: resolvedFrames)

        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frames = resolvedFrames
        self.samples = samples
    }

    private enum CodingKeys: String, CodingKey {
        case sampleRate
        case channelCount
        case frames
        case samples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        let channelCount = try container.decode(Int.self, forKey: .channelCount)
        let frames = try container.decode(Int.self, forKey: .frames)
        let samples = try container.decode([[Float]].self, forKey: .samples)

        try self.init(
            sampleRate: sampleRate,
            channelCount: channelCount,
            frames: frames,
            samples: samples
        )
    }

    private static func validate(samples: [[Float]], expectedFrames: Int) throws {
        for (channelIndex, channelSamples) in samples.enumerated() {
            guard channelSamples.count == expectedFrames else {
                throw AudioBufferError.frameCountMismatch(
                    channel: channelIndex,
                    expected: expectedFrames,
                    actual: channelSamples.count
                )
            }

            for (frameIndex, sample) in channelSamples.enumerated() {
                guard sample.isFinite else {
                    throw AudioBufferError.nonFiniteSample(
                        channel: channelIndex,
                        frame: frameIndex
                    )
                }
            }
        }
    }
}
