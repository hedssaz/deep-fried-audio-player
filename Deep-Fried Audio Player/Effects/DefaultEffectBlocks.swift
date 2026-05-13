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
    static let mode = "mode"
    static let cutoff = "cutoff"
    static let lowCut = "lowCut"
    static let highCut = "highCut"
    static let centerFrequency = "centerFrequency"
    static let resonance = "resonance"
    static let slope = "slope"
    static let gainRange = "gainRange"
    static let bandCount = "bandCount"
    static let seed = "seed"
    static let mix = "mix"
    static let width = "width"
    static let depth = "depth"
    static let frequencyRange = "frequencyRange"
    static let intensity = "intensity"
    static let ratio = "ratio"
    static let attack = "attack"
    static let release = "release"
    static let makeupGain = "makeupGain"
    static let componentCount = "componentCount"
    static let windowSize = "windowSize"
    static let overlap = "overlap"
    static let minFrequency = "minFrequency"
    static let maxFrequency = "maxFrequency"
    static let preservePhase = "preservePhase"
    static let codec = "codec"
    static let bitRateKbps = "bitRateKbps"
}

nonisolated enum FilterEQMode: String, CaseIterable, Codable, Sendable {
    case lowPass
    case highPass
    case bandPass
    case notch
    case randomFrequencyResponse

    var labelKey: String {
        switch self {
        case .lowPass:
            "choice.filterMode.lowPass"
        case .highPass:
            "choice.filterMode.highPass"
        case .bandPass:
            "choice.filterMode.bandPass"
        case .notch:
            "choice.filterMode.notch"
        case .randomFrequencyResponse:
            "choice.filterMode.randomFrequencyResponse"
        }
    }
}

nonisolated enum SpectralDamageMode: String, CaseIterable, Codable, Sendable {
    case keepTopKFrequencyBins

    var labelKey: String {
        switch self {
        case .keepTopKFrequencyBins:
            "choice.spectralMode.keepTopKFrequencyBins"
        }
    }
}

extension EffectType {
    static let userFacingNonCodecEffectTypes: [EffectType] = [
        .sampleRateReduction,
        .bitDepthReduction,
        .clipping,
        .filterEQ,
        .compressor,
        .limiter,
        .spectralDamage,
    ]

    static let firstRealEffectTypes = userFacingNonCodecEffectTypes

    static var userFacingCodecEffectTypes: [EffectType] {
        CodecCapabilityCatalog.current.hasAvailableRoundTripCodec
            ? [.bitrateReduction, .lowQualityCodec]
            : []
    }

    static var availableUserFacingEffectTypes: [EffectType] {
        userFacingNonCodecEffectTypes + userFacingCodecEffectTypes
    }

    static let legacyIndividualFilterTypes: [EffectType] = [
        .lowPass,
        .highPass,
        .bandPass,
        .notch,
        .randomFrequencyResponse,
    ]

    var displayNameKey: String {
        switch self {
        case .sampleRateReduction:
            "effect.sampleRateReduction"
        case .bitDepthReduction:
            "effect.bitDepthReduction"
        case .clipping:
            "effect.clipping"
        case .filterEQ:
            "effect.filterEQ"
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
        case .filterEQ:
            [
                EffectParameter(
                    key: EffectParameterKey.mode,
                    labelKey: "parameter.mode",
                    value: .choice(FilterEQMode.lowPass.rawValue),
                    choices: FilterEQMode.allCases.map {
                        EffectParameterChoice(value: $0.rawValue, labelKey: $0.labelKey)
                    }
                ),
                EffectParameter(
                    key: EffectParameterKey.cutoff,
                    labelKey: "parameter.cutoff",
                    value: .float(3_200),
                    valueRange: .float(min: 80, max: 18_000),
                    unitKey: "unit.hz"
                ),
                EffectParameter(
                    key: EffectParameterKey.lowCut,
                    labelKey: "parameter.lowCut",
                    value: .float(300),
                    valueRange: .float(min: 20, max: 8_000),
                    unitKey: "unit.hz"
                ),
                EffectParameter(
                    key: EffectParameterKey.highCut,
                    labelKey: "parameter.highCut",
                    value: .float(3_400),
                    valueRange: .float(min: 500, max: 20_000),
                    unitKey: "unit.hz"
                ),
                EffectParameter(
                    key: EffectParameterKey.centerFrequency,
                    labelKey: "parameter.centerFrequency",
                    value: .float(1_000),
                    valueRange: .float(min: 80, max: 12_000),
                    unitKey: "unit.hz"
                ),
                EffectParameter(
                    key: EffectParameterKey.resonance,
                    labelKey: "parameter.resonance",
                    value: .float(0.85),
                    valueRange: .float(min: 0.2, max: 12.0),
                    unitKey: "unit.q"
                ),
                EffectParameter(
                    key: EffectParameterKey.slope,
                    labelKey: "parameter.slope",
                    value: .choice("12"),
                    choices: [
                        EffectParameterChoice(value: "12", labelKey: "choice.slope.12"),
                        EffectParameterChoice(value: "24", labelKey: "choice.slope.24"),
                    ],
                    unitKey: "unit.dbPerOctave"
                ),
                EffectParameter(
                    key: EffectParameterKey.width,
                    labelKey: "parameter.width",
                    value: .float(1.0),
                    valueRange: .float(min: 0.05, max: 4.0),
                    unitKey: "unit.octave"
                ),
                EffectParameter(
                    key: EffectParameterKey.depth,
                    labelKey: "parameter.depth",
                    value: .float(1.0),
                    valueRange: .float(min: 0.0, max: 1.0),
                    unitKey: "unit.linear"
                ),
                EffectParameter(
                    key: EffectParameterKey.frequencyRange,
                    labelKey: "parameter.frequencyRange",
                    value: .range(EffectParameterRangeValue(lowerBound: 120, upperBound: 12_000)),
                    valueRange: .range(min: 20, max: 20_000),
                    unitKey: "unit.hz"
                ),
                EffectParameter(
                    key: EffectParameterKey.gainRange,
                    labelKey: "parameter.gainRange",
                    value: .range(EffectParameterRangeValue(lowerBound: -10, upperBound: 10)),
                    valueRange: .range(min: -24, max: 24),
                    unitKey: "unit.db"
                ),
                EffectParameter(
                    key: EffectParameterKey.bandCount,
                    labelKey: "parameter.bandCount",
                    value: .int(8),
                    valueRange: .int(min: 2, max: 24)
                ),
                EffectParameter(
                    key: EffectParameterKey.seed,
                    labelKey: "parameter.seed",
                    value: .int(1_337),
                    valueRange: .int(min: 0, max: 999_999)
                ),
                EffectParameter(
                    key: EffectParameterKey.intensity,
                    labelKey: "parameter.intensity",
                    value: .float(1.0),
                    valueRange: .float(min: 0.0, max: 1.0),
                    unitKey: "unit.linear"
                ),
                EffectParameter(
                    key: EffectParameterKey.mix,
                    labelKey: "parameter.mix",
                    value: .float(1.0),
                    valueRange: .float(min: 0.0, max: 1.0),
                    unitKey: "unit.linear"
                ),
            ]
        case .compressor:
            [
                EffectParameter(
                    key: EffectParameterKey.threshold,
                    labelKey: "parameter.threshold",
                    value: .float(-18.0),
                    valueRange: .float(min: -60.0, max: 0.0),
                    unitKey: "unit.db"
                ),
                EffectParameter(
                    key: EffectParameterKey.ratio,
                    labelKey: "parameter.ratio",
                    value: .float(8.0),
                    valueRange: .float(min: 1.0, max: 20.0),
                    unitKey: "unit.ratio"
                ),
                EffectParameter(
                    key: EffectParameterKey.attack,
                    labelKey: "parameter.attack",
                    value: .float(5.0),
                    valueRange: .float(min: 0.1, max: 100.0),
                    unitKey: "unit.ms"
                ),
                EffectParameter(
                    key: EffectParameterKey.release,
                    labelKey: "parameter.release",
                    value: .float(80.0),
                    valueRange: .float(min: 5.0, max: 1_000.0),
                    unitKey: "unit.ms"
                ),
                EffectParameter(
                    key: EffectParameterKey.inputGain,
                    labelKey: "parameter.inputGain",
                    value: .float(1.0),
                    valueRange: .float(min: 0.1, max: 20.0),
                    unitKey: "unit.multiplier"
                ),
                EffectParameter(
                    key: EffectParameterKey.makeupGain,
                    labelKey: "parameter.makeupGain",
                    value: .float(1.4),
                    valueRange: .float(min: 0.1, max: 20.0),
                    unitKey: "unit.multiplier"
                ),
                EffectParameter(
                    key: EffectParameterKey.mix,
                    labelKey: "parameter.mix",
                    value: .float(1.0),
                    valueRange: .float(min: 0.0, max: 1.0),
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
        case .spectralDamage:
            [
                EffectParameter(
                    key: EffectParameterKey.mode,
                    labelKey: "parameter.mode",
                    value: .choice(SpectralDamageMode.keepTopKFrequencyBins.rawValue),
                    choices: [
                        EffectParameterChoice(
                            value: SpectralDamageMode.keepTopKFrequencyBins.rawValue,
                            labelKey: SpectralDamageMode.keepTopKFrequencyBins.labelKey
                        ),
                    ]
                ),
                EffectParameter(
                    key: EffectParameterKey.componentCount,
                    labelKey: "parameter.componentCount",
                    value: .int(12),
                    valueRange: .int(min: 1, max: 128)
                ),
                EffectParameter(
                    key: EffectParameterKey.windowSize,
                    labelKey: "parameter.windowSize",
                    value: .choice("512"),
                    choices: [
                        EffectParameterChoice(value: "128", labelKey: "choice.windowSize.128"),
                        EffectParameterChoice(value: "256", labelKey: "choice.windowSize.256"),
                        EffectParameterChoice(value: "512", labelKey: "choice.windowSize.512"),
                        EffectParameterChoice(value: "1024", labelKey: "choice.windowSize.1024"),
                    ],
                    unitKey: "unit.samples"
                ),
                EffectParameter(
                    key: EffectParameterKey.overlap,
                    labelKey: "parameter.overlap",
                    value: .float(0.5),
                    valueRange: .float(min: 0.0, max: 0.875),
                    unitKey: "unit.linear"
                ),
                EffectParameter(
                    key: EffectParameterKey.minFrequency,
                    labelKey: "parameter.minFrequency",
                    value: .float(80.0),
                    valueRange: .float(min: 20.0, max: 12_000.0),
                    unitKey: "unit.hz"
                ),
                EffectParameter(
                    key: EffectParameterKey.maxFrequency,
                    labelKey: "parameter.maxFrequency",
                    value: .float(12_000.0),
                    valueRange: .float(min: 100.0, max: 20_000.0),
                    unitKey: "unit.hz"
                ),
                EffectParameter(
                    key: EffectParameterKey.preservePhase,
                    labelKey: "parameter.preservePhase",
                    value: .bool(true)
                ),
                EffectParameter(
                    key: EffectParameterKey.mix,
                    labelKey: "parameter.mix",
                    value: .float(1.0),
                    valueRange: .float(min: 0.0, max: 1.0),
                    unitKey: "unit.linear"
                ),
            ]
        case .bitrateReduction:
            Self.codecDefaultParameters(defaultBitRateKbps: 48)
        case .lowQualityCodec:
            Self.codecDefaultParameters(defaultBitRateKbps: 24)
        case .lowPass,
             .highPass,
             .bandPass,
             .notch,
             .randomFrequencyResponse:
            []
        }
    }

    private static func codecDefaultParameters(defaultBitRateKbps: Int) -> [EffectParameter] {
        let catalog = CodecCapabilityCatalog.current
        let choices = catalog.availableRoundTripChoices()

        guard let defaultCapability = catalog.defaultRoundTripCapability,
              !choices.isEmpty else {
            return []
        }

        let bitRateRange = defaultCapability.bitRateRange ?? CodecBitRateRange(
            minKbps: 16,
            maxKbps: 320
        )
        let clampedDefaultBitRate = defaultBitRateKbps.clamped(to: bitRateRange.closedRange)

        return [
            EffectParameter(
                key: EffectParameterKey.codec,
                labelKey: "parameter.codec",
                value: .choice(defaultCapability.id.rawValue),
                choices: choices
            ),
            EffectParameter(
                key: EffectParameterKey.bitRateKbps,
                labelKey: "parameter.bitRateKbps",
                value: .int(clampedDefaultBitRate),
                valueRange: .int(
                    min: bitRateRange.minKbps,
                    max: bitRateRange.maxKbps
                ),
                unitKey: "unit.kbps"
            ),
        ]
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

    var visibleParameters: [EffectParameter] {
        guard type == .filterEQ else {
            if type == .spectralDamage {
                return parameters.filter { $0.key != EffectParameterKey.preservePhase }
            }

            return parameters
        }

        let mode = filterEQMode
        let visibleKeys: [String] = switch mode {
        case .lowPass, .highPass:
            [
                EffectParameterKey.mode,
                EffectParameterKey.mix,
                EffectParameterKey.resonance,
                EffectParameterKey.slope,
                EffectParameterKey.cutoff,
            ]
        case .bandPass:
            [
                EffectParameterKey.mode,
                EffectParameterKey.mix,
                EffectParameterKey.resonance,
                EffectParameterKey.slope,
                EffectParameterKey.lowCut,
                EffectParameterKey.highCut,
            ]
        case .notch:
            [
                EffectParameterKey.mode,
                EffectParameterKey.mix,
                EffectParameterKey.resonance,
                EffectParameterKey.slope,
                EffectParameterKey.centerFrequency,
                EffectParameterKey.width,
                EffectParameterKey.depth,
            ]
        case .randomFrequencyResponse:
            [
                EffectParameterKey.mode,
                EffectParameterKey.mix,
                EffectParameterKey.resonance,
                EffectParameterKey.slope,
                EffectParameterKey.bandCount,
                EffectParameterKey.frequencyRange,
                EffectParameterKey.gainRange,
                EffectParameterKey.seed,
                EffectParameterKey.intensity,
            ]
        }

        return visibleKeys.compactMap { key in
            parameters.first { $0.key == key }
        }
    }

    var filterEQMode: FilterEQMode {
        guard let parameter = parameters.first(where: { $0.key == EffectParameterKey.mode }),
              case let .choice(value) = parameter.value,
              let mode = FilterEQMode(rawValue: value) else {
            return .lowPass
        }

        return mode
    }
}
