//
//  DefaultEffectBlocks.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated enum EffectParameterKey {
    static let targetSampleRate = "targetSampleRate"
    static let bits = "bits"
    static let drive = "drive"
    static let threshold = "threshold"
    static let inputGain = "inputGain"
    static let ceiling = "ceiling"
}

extension EffectType {
    static let firstRealEffectTypes: [EffectType] = [
        .sampleRateReduction,
        .bitDepthReduction,
        .clipping,
        .limiter,
    ]

    var displayNameKey: String {
        switch self {
        case .sampleRateReduction:
            "effect.sampleRateReduction"
        case .bitDepthReduction:
            "effect.bitDepthReduction"
        case .clipping:
            "effect.clipping"
        case .lowPass:
            "effect.lowPass"
        case .highPass:
            "effect.highPass"
        case .bandPass:
            "effect.bandPass"
        case .notch:
            "effect.notch"
        case .compressor:
            "effect.compressor"
        case .limiter:
            "effect.limiter"
        case .randomFrequencyResponse:
            "effect.randomFrequencyResponse"
        case .spectralDamage:
            "effect.spectralDamage"
        case .bitrateReduction:
            "effect.bitrateReduction"
        case .lowQualityCodec:
            "effect.lowQualityCodec"
        }
    }

    var defaultParameters: [EffectParameter] {
        switch self {
        case .sampleRateReduction:
            [
                EffectParameter(
                    key: EffectParameterKey.targetSampleRate,
                    labelKey: "parameter.targetSampleRate",
                    value: .choice("11025"),
                    choices: [
                        EffectParameterChoice(value: "44100", labelKey: "choice.sampleRate.44100"),
                        EffectParameterChoice(value: "22050", labelKey: "choice.sampleRate.22050"),
                        EffectParameterChoice(value: "16000", labelKey: "choice.sampleRate.16000"),
                        EffectParameterChoice(value: "11025", labelKey: "choice.sampleRate.11025"),
                        EffectParameterChoice(value: "8000", labelKey: "choice.sampleRate.8000"),
                    ],
                    unitKey: "unit.hz"
                ),
            ]
        case .bitDepthReduction:
            [
                EffectParameter(
                    key: EffectParameterKey.bits,
                    labelKey: "parameter.bits",
                    value: .int(6),
                    valueRange: .int(min: 1, max: 16),
                    unitKey: "unit.bit"
                ),
            ]
        case .clipping:
            [
                EffectParameter(
                    key: EffectParameterKey.drive,
                    labelKey: "parameter.drive",
                    value: .float(2.5),
                    valueRange: .float(min: 1.0, max: 20.0),
                    unitKey: "unit.multiplier"
                ),
                EffectParameter(
                    key: EffectParameterKey.threshold,
                    labelKey: "parameter.threshold",
                    value: .float(0.45),
                    valueRange: .float(min: 0.05, max: 1.0),
                    unitKey: "unit.linear"
                ),
            ]
        case .limiter:
            [
                EffectParameter(
                    key: EffectParameterKey.inputGain,
                    labelKey: "parameter.inputGain",
                    value: .float(3.0),
                    valueRange: .float(min: 1.0, max: 20.0),
                    unitKey: "unit.multiplier"
                ),
                EffectParameter(
                    key: EffectParameterKey.ceiling,
                    labelKey: "parameter.ceiling",
                    value: .float(0.92),
                    valueRange: .float(min: 0.1, max: 1.0),
                    unitKey: "unit.linear"
                ),
            ]
        case .lowPass,
             .highPass,
             .bandPass,
             .notch,
             .compressor,
             .randomFrequencyResponse,
             .spectralDamage,
             .bitrateReduction,
             .lowQualityCodec:
            []
        }
    }
}

extension EffectBlock {
    static func defaultBlock(
        id: UUID = UUID(),
        type: EffectType,
        order: Int,
        isEnabled: Bool = true,
        presetName: String? = nil
    ) -> EffectBlock {
        EffectBlock(
            id: id,
            type: type,
            name: type.displayNameKey,
            isEnabled: isEnabled,
            order: order,
            parameters: type.defaultParameters,
            presetName: presetName
        )
    }
}
