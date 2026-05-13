//
//  EffectType.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated enum EffectType: String, CaseIterable, Codable, Identifiable, Sendable {
    case sampleRateReduction = "sample-rate-reduction"
    case bitDepthReduction = "bit-depth-reduction"
    case clipping
    case filterEQ = "filter-eq"
    case lowPass = "low-pass"
    case highPass = "high-pass"
    case bandPass = "band-pass"
    case notch
    case compressor
    case limiter
    case randomFrequencyResponse = "random-frequency-response"
    case spectralDamage = "spectral-damage"
    case bitrateReduction = "bitrate-reduction"
    case lowQualityCodec = "low-quality-codec"

    var id: String { rawValue }
}
