//
//  EffectParameter.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct EffectParameter: Codable, Equatable, Identifiable {
    var id: String { key }

    let key: String
    let labelKey: String
    var value: EffectParameterValue
    var valueRange: EffectParameterValueRange?
    var choices: [EffectParameterChoice]
    var unitKey: String?

    init(
        key: String,
        labelKey: String,
        value: EffectParameterValue,
        valueRange: EffectParameterValueRange? = nil,
        choices: [EffectParameterChoice] = [],
        unitKey: String? = nil
    ) {
        self.key = key
        self.labelKey = labelKey
        self.value = value
        self.valueRange = valueRange
        self.choices = choices
        self.unitKey = unitKey
    }
}

enum EffectParameterKind: String, Codable, Equatable {
    case float
    case int
    case bool
    case choice
    case range
}

enum EffectParameterValue: Codable, Equatable {
    case float(Double)
    case int(Int)
    case bool(Bool)
    case choice(String)
    case range(EffectParameterRangeValue)

    var kind: EffectParameterKind {
        switch self {
        case .float:
            .float
        case .int:
            .int
        case .bool:
            .bool
        case .choice:
            .choice
        case .range:
            .range
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case floatValue
        case intValue
        case boolValue
        case choiceValue
        case rangeValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(EffectParameterKind.self, forKey: .kind)

        switch kind {
        case .float:
            self = .float(try container.decode(Double.self, forKey: .floatValue))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .intValue))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .boolValue))
        case .choice:
            self = .choice(try container.decode(String.self, forKey: .choiceValue))
        case .range:
            self = .range(try container.decode(EffectParameterRangeValue.self, forKey: .rangeValue))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case let .float(value):
            try container.encode(value, forKey: .floatValue)
        case let .int(value):
            try container.encode(value, forKey: .intValue)
        case let .bool(value):
            try container.encode(value, forKey: .boolValue)
        case let .choice(value):
            try container.encode(value, forKey: .choiceValue)
        case let .range(value):
            try container.encode(value, forKey: .rangeValue)
        }
    }
}

enum EffectParameterValueRange: Codable, Equatable {
    case float(min: Double, max: Double)
    case int(min: Int, max: Int)
    case range(min: Double, max: Double)

    private enum CodingKeys: String, CodingKey {
        case kind
        case floatMin
        case floatMax
        case intMin
        case intMax
        case rangeMin
        case rangeMax
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(EffectParameterKind.self, forKey: .kind)

        switch kind {
        case .float:
            self = .float(
                min: try container.decode(Double.self, forKey: .floatMin),
                max: try container.decode(Double.self, forKey: .floatMax)
            )
        case .int:
            self = .int(
                min: try container.decode(Int.self, forKey: .intMin),
                max: try container.decode(Int.self, forKey: .intMax)
            )
        case .range:
            self = .range(
                min: try container.decode(Double.self, forKey: .rangeMin),
                max: try container.decode(Double.self, forKey: .rangeMax)
            )
        case .bool, .choice:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Bool and choice parameters do not use numeric ranges."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .float(min, max):
            try container.encode(EffectParameterKind.float, forKey: .kind)
            try container.encode(min, forKey: .floatMin)
            try container.encode(max, forKey: .floatMax)
        case let .int(min, max):
            try container.encode(EffectParameterKind.int, forKey: .kind)
            try container.encode(min, forKey: .intMin)
            try container.encode(max, forKey: .intMax)
        case let .range(min, max):
            try container.encode(EffectParameterKind.range, forKey: .kind)
            try container.encode(min, forKey: .rangeMin)
            try container.encode(max, forKey: .rangeMax)
        }
    }
}

struct EffectParameterChoice: Codable, Equatable, Identifiable {
    var id: String { value }

    let value: String
    let labelKey: String

    init(value: String, labelKey: String) {
        self.value = value
        self.labelKey = labelKey
    }
}

struct EffectParameterRangeValue: Codable, Equatable {
    var lowerBound: Double
    var upperBound: Double

    init(lowerBound: Double, upperBound: Double) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}
