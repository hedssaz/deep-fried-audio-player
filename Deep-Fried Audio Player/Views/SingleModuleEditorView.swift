//
//  SingleModuleEditorView.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

struct SingleModuleEditorView: View {
    @ObservedObject var project: AudioProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            modulePicker
            parameterSection
            presetSection
            sendToWorkflowButton

            if let statusKey = project.singleModuleStatusKey {
                Label(LocalizedStringKey(statusKey), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("singleModuleStatus")
            }
        }
    }

    private var modulePicker: some View {
        Picker(
            "singleModule.modulePicker",
            selection: Binding(
                get: { project.selectedSingleModule.type },
                set: { project.selectSingleModuleType($0) }
            )
        ) {
            ForEach(project.availableSingleModuleTypes) { type in
                Text(LocalizedStringKey(type.displayNameKey)).tag(type)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("singleModulePicker")
    }

    @ViewBuilder
    private var parameterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("singleModule.parameters", systemImage: "slider.horizontal.3")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if project.selectedSingleModule.parameters.isEmpty {
                Text("singleModule.noParameters")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(project.selectedSingleModule.parameters) { parameter in
                    EffectParameterEditor(parameter: parameter) { value in
                        project.updateSingleModuleParameter(key: parameter.key, value: value)
                    }
                }
            }
        }
        .accessibilityIdentifier("singleModuleParameters")
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("singleModule.presets", systemImage: "tray.full")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(
                "singleModule.presetName",
                text: $project.modulePresetName
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("modulePresetNameField")

            Picker(
                "singleModule.savedPresets",
                selection: $project.selectedModulePresetID
            ) {
                Text("singleModule.noPresetSelected").tag(Optional<ModulePreset.ID>.none)
                ForEach(project.modulePresets) { preset in
                    Text(verbatim: preset.name).tag(Optional(preset.id))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("modulePresetPicker")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    presetButtons
                }

                VStack(alignment: .leading, spacing: 10) {
                    presetButtons
                }
            }
        }
        .accessibilityIdentifier("singleModulePresets")
    }

    @ViewBuilder
    private var presetButtons: some View {
        Button {
            Task {
                await project.saveCurrentModulePreset()
            }
        } label: {
            Label("singleModule.savePreset", systemImage: "tray.and.arrow.down")
        }
        .buttonStyle(.bordered)
        .disabled(project.modulePresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("saveModulePresetButton")

        Button {
            Task {
                await project.loadSelectedModulePreset()
            }
        } label: {
            Label("singleModule.loadPreset", systemImage: "tray.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .disabled(project.selectedModulePresetID == nil)
        .accessibilityIdentifier("loadModulePresetButton")
    }

    private var sendToWorkflowButton: some View {
        Button {
            project.sendSingleModuleToWorkflow()
        } label: {
            Label("singleModule.sendToWorkflow", systemImage: "arrow.right.square")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("sendModuleToWorkflowButton")
    }
}

private struct EffectParameterEditor: View {
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
        .accessibilityIdentifier("parameterEditor.\(parameter.key)")
    }

    @ViewBuilder
    private var parameterValueText: some View {
        if let unitKey = parameter.unitKey {
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
                parameter.labelKey,
                selection: Binding(
                    get: { choiceValue },
                    set: { onChange(.choice($0)) }
                )
            ) {
                ForEach(parameter.choices) { choice in
                    Text(LocalizedStringKey(choice.labelKey)).tag(choice.value)
                }
            }
            .pickerStyle(.menu)
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
        case .float:
            Slider(
                value: Binding(
                    get: { floatValue },
                    set: { onChange(.float($0)) }
                ),
                in: floatRange
            )
        case .bool:
            Toggle(
                parameter.labelKey,
                isOn: Binding(
                    get: { boolValue },
                    set: { onChange(.bool($0)) }
                )
            )
            .labelsHidden()
        case .range:
            VStack(spacing: 8) {
                LabeledContent("singleModule.rangeLower") {
                    Slider(
                        value: Binding(
                            get: { rangeValue.lowerBound },
                            set: { onChange(.range(EffectParameterRangeValue(lowerBound: $0, upperBound: rangeValue.upperBound))) }
                        ),
                        in: rangeLimits
                    )
                }
                LabeledContent("singleModule.rangeUpper") {
                    Slider(
                        value: Binding(
                            get: { rangeValue.upperBound },
                            set: { onChange(.range(EffectParameterRangeValue(lowerBound: rangeValue.lowerBound, upperBound: $0))) }
                        ),
                        in: rangeLimits
                    )
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
