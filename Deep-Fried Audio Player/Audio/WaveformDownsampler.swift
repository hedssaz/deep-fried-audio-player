//
//  WaveformDownsampler.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct WaveformSample: Equatable, Identifiable {
    let index: Int
    let minimum: Float
    let maximum: Float

    var id: Int { index }
}

enum WaveformDownsampler {
    static func downsample(
        _ buffer: AudioBuffer,
        targetSampleCount: Int
    ) -> [WaveformSample] {
        guard buffer.frames > 0, targetSampleCount > 0 else {
            return []
        }

        let bucketCount = min(buffer.frames, targetSampleCount)
        let framesPerBucket = Double(buffer.frames) / Double(bucketCount)

        return (0..<bucketCount).map { bucketIndex in
            let startFrame = Int((Double(bucketIndex) * framesPerBucket).rounded(.down))
            let rawEndFrame = Int((Double(bucketIndex + 1) * framesPerBucket).rounded(.down))
            let endFrame = min(buffer.frames, max(startFrame + 1, rawEndFrame))
            var minimum = Float.greatestFiniteMagnitude
            var maximum = -Float.greatestFiniteMagnitude

            for channelSamples in buffer.samples {
                for frameIndex in startFrame..<endFrame {
                    let sample = channelSamples[frameIndex]
                    minimum = min(minimum, sample)
                    maximum = max(maximum, sample)
                }
            }

            return WaveformSample(
                index: bucketIndex,
                minimum: minimum,
                maximum: maximum
            )
        }
    }
}
