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

            let visibleParameters = project.selectedSingleModule.visibleParameters
            if visibleParameters.isEmpty {
                Text("singleModule.noParameters")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleParameters) { parameter in
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
