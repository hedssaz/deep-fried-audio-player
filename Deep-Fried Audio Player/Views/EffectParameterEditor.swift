//
//  EffectParameterEditor.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

struct EffectParameterEditor: View {
    let parameter: EffectParameter
    let onChange: (EffectParameterValue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(parameter.labelKey))
                    .font(.callout)
                Spacer(minLength: 12)
                parameterValueText
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            parameterControl
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("parameterEditor.\(parameter.key)")
    }

    @ViewBuilder
    private var parameterValueText: some View {
        if case .choice = parameter.value,
           let choice = selectedChoice {
            Text(LocalizedStringKey(choice.labelKey))
        } else if let unitKey = parameter.unitKey {
            HStack(spacing: 3) {
                Text(verbatim: formattedValue)
                Text(LocalizedStringKey(unitKey))
            }
        } else {
            Text(verbatim: formattedValue)
        }
    }

    @ViewBuilder
    private var parameterControl: some View {
        switch parameter.value {
        case .choice:
            Picker(
                LocalizedStringKey(parameter.labelKey),
                selection: Binding(
                    get: { choiceValue },
                    set: { onChange(.choice($0)) }
                )
            ) {
                ForEach(parameter.choices) { choice in
                    Text(LocalizedStringKey(choice.labelKey))
                        .tag(choice.value)
                        .accessibilityIdentifier("parameterChoice.\(parameter.key).\(choice.value)")
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("parameterControl.\(parameter.key).choice")
        case .int:
            Stepper(
                value: Binding(
                    get: { intValue },
                    set: { onChange(.int($0)) }
                ),
                in: intRange
            ) {
                EmptyView()
            }
            .accessibilityIdentifier("parameterControl.\(parameter.key).int")
        case .float:
            Slider(
                value: Binding(
                    get: { floatValue },
                    set: { onChange(.float($0)) }
                ),
                in: floatRange
            )
            .accessibilityIdentifier("parameterControl.\(parameter.key).float")
        case .bool:
            Toggle(
                LocalizedStringKey(parameter.labelKey),
                isOn: Binding(
                    get: { boolValue },
                    set: { onChange(.bool($0)) }
                )
            )
            .labelsHidden()
            .accessibilityIdentifier("parameterControl.\(parameter.key).bool")
        case .range:
            VStack(spacing: 8) {
                LabeledContent("parameter.rangeLower") {
                    Slider(
                        value: Binding(
                            get: { rangeValue.lowerBound },
                            set: { onChange(.range(EffectParameterRangeValue(lowerBound: $0, upperBound: rangeValue.upperBound))) }
                        ),
                        in: rangeLimits
                    )
                    .accessibilityIdentifier("parameterControl.\(parameter.key).rangeLower")
                }
                LabeledContent("parameter.rangeUpper") {
                    Slider(
                        value: Binding(
                            get: { rangeValue.upperBound },
                            set: { onChange(.range(EffectParameterRangeValue(lowerBound: rangeValue.lowerBound, upperBound: $0))) }
                        ),
                        in: rangeLimits
                    )
                    .accessibilityIdentifier("parameterControl.\(parameter.key).rangeUpper")
                }
            }
        }
    }

    private var formattedValue: String {
        switch parameter.value {
        case let .choice(value):
            parameter.choices.first { $0.value == value }?.value ?? value
        case let .int(value):
            "\(value)"
        case let .float(value):
            String(format: "%.2f", value)
        case let .bool(value):
            value ? "1" : "0"
        case let .range(value):
            "\(Int(value.lowerBound))-\(Int(value.upperBound))"
        }
    }

    private var choiceValue: String {
        if case let .choice(value) = parameter.value {
            return value
        }

        return parameter.choices.first?.value ?? ""
    }

    private var selectedChoice: EffectParameterChoice? {
        guard case let .choice(value) = parameter.value else {
            return nil
        }

        return parameter.choices.first { $0.value == value }
    }

    private var intValue: Int {
        if case let .int(value) = parameter.value {
            return value
        }

        return intRange.lowerBound
    }

    private var intRange: ClosedRange<Int> {
        if case let .int(min, max) = parameter.valueRange {
            return min...max
        }

        return 0...100
    }

    private var floatValue: Double {
        if case let .float(value) = parameter.value {
            return value
        }

        return floatRange.lowerBound
    }

    private var floatRange: ClosedRange<Double> {
        if case let .float(min, max) = parameter.valueRange {
            return min...max
        }

        return 0...1
    }

    private var boolValue: Bool {
        if case let .bool(value) = parameter.value {
            return value
        }

        return false
    }

    private var rangeValue: EffectParameterRangeValue {
        if case let .range(value) = parameter.value {
            return value
        }

        return EffectParameterRangeValue(
            lowerBound: rangeLimits.lowerBound,
            upperBound: rangeLimits.upperBound
        )
    }

    private var rangeLimits: ClosedRange<Double> {
        if case let .range(min, max) = parameter.valueRange {
            return min...max
        }

        return 0...1
    }
}
