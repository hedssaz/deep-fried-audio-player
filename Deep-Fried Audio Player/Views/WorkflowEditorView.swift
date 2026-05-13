//
//  WorkflowEditorView.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

struct WorkflowEditorView: View {
    @ObservedObject var project: AudioProjectViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            regularLayout
        } else {
            compactLayout
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            addModuleSection
            blockListSection(showsInlineParameters: true, highlightsSelection: false)
            presetSection
            statusView
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                addModuleSection
                blockListSection(showsInlineParameters: false, highlightsSelection: true)
            }
            .frame(minWidth: 280, maxWidth: 360, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                selectedBlockDetailSection
                presetSection
                statusView
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var addModuleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("workflow.addModule", systemImage: "plus.square.on.square")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker(
                "workflow.modulePicker",
                selection: $project.selectedWorkflowModuleType
            ) {
                ForEach(project.availableWorkflowModuleTypes) { type in
                    Text(LocalizedStringKey(type.displayNameKey)).tag(type)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("workflowModulePicker")

            Button {
                project.addWorkflowBlock()
            } label: {
                Label("workflow.addModule", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("addWorkflowModuleButton")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workflowAddModuleSection")
    }

    private func blockListSection(
        showsInlineParameters: Bool,
        highlightsSelection: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("workflow.blocks", systemImage: "square.stack.3d.up")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let orderedBlocks = project.currentWorkflow.orderedBlocks
            if orderedBlocks.isEmpty {
                Text("workflow.empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("workflowEmptyState")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(orderedBlocks.enumerated()), id: \.element.id) { index, block in
                        WorkflowBlockRow(
                            project: project,
                            block: block,
                            index: index,
                            isFirst: index == orderedBlocks.startIndex,
                            isLast: index == orderedBlocks.index(before: orderedBlocks.endIndex),
                            isSelected: highlightsSelection && block.id == project.selectedWorkflowBlockID,
                            showsInlineParameters: showsInlineParameters
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("workflowBlockList")
            }
        }
    }

    private var selectedBlockDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("workflow.moduleDetails", systemImage: "slider.horizontal.3")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let selectedBlock = project.selectedWorkflowBlock {
                selectedBlockParameterPanel(selectedBlock)
            } else {
                Text(LocalizedStringKey(project.currentWorkflow.orderedBlocks.isEmpty ? "workflow.empty" : "workflow.selectModulePrompt"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("workflowSelectionPrompt")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workflowModuleDetails")
    }

    private func selectedBlockParameterPanel(_ block: EffectBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label {
                    Text(LocalizedStringKey(block.type.displayNameKey))
                        .font(.headline)
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }

                Spacer(minLength: 12)

                Text(verbatim: blockOrderText(for: block))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "workflow.blockEnabled",
                isOn: Binding(
                    get: { block.isEnabled },
                    set: { project.setWorkflowBlockEnabled(id: block.id, isEnabled: $0) }
                )
            )
            .accessibilityIdentifier("workflowSelectedBlockEnabled.\(block.id.uuidString)")

            let visibleParameters = block.visibleParameters
            if visibleParameters.isEmpty {
                Text("workflow.noParameters")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleParameters) { parameter in
                        EffectParameterEditor(parameter: parameter) { value in
                            project.updateWorkflowBlockParameter(
                                blockID: block.id,
                                key: parameter.key,
                                value: value
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("workflowSelectedBlockParameters")
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("workflow.presets", systemImage: "tray.full")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(
                "workflow.presetName",
                text: $project.workflowPresetName
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("workflowPresetNameField")

            Picker(
                "workflow.savedPresets",
                selection: $project.selectedWorkflowPresetID
            ) {
                Text("workflow.noPresetSelected").tag(Optional<WorkflowPreset.ID>.none)
                ForEach(project.workflowPresets) { preset in
                    Text(verbatim: preset.name).tag(Optional(preset.id))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("workflowPresetPicker")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    presetButtons
                }

                VStack(alignment: .leading, spacing: 10) {
                    presetButtons
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workflowPresets")
    }

    @ViewBuilder
    private var presetButtons: some View {
        Button {
            Task {
                await project.saveCurrentWorkflowPreset()
            }
        } label: {
            Label("workflow.savePreset", systemImage: "tray.and.arrow.down")
        }
        .buttonStyle(.bordered)
        .disabled(project.workflowPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("saveWorkflowPresetButton")

        Button {
            Task {
                await project.loadSelectedWorkflowPreset()
            }
        } label: {
            Label("workflow.loadPreset", systemImage: "tray.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .disabled(project.selectedWorkflowPresetID == nil)
        .accessibilityIdentifier("loadWorkflowPresetButton")
    }

    @ViewBuilder
    private var statusView: some View {
        if let statusKey = project.workflowStatusKey {
            Label(LocalizedStringKey(statusKey), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("workflowStatus")
        }
    }

    private func blockOrderText(for block: EffectBlock) -> String {
        guard let index = project.currentWorkflow.orderedBlocks.firstIndex(where: { $0.id == block.id }) else {
            return ""
        }

        return "#\(index + 1)"
    }
}

private struct WorkflowBlockRow: View {
    @ObservedObject var project: AudioProjectViewModel
    let block: EffectBlock
    let index: Int
    let isFirst: Bool
    let isLast: Bool
    let isSelected: Bool
    let showsInlineParameters: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label {
                        Text(LocalizedStringKey(block.type.displayNameKey))
                            .font(.headline)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }

                    Spacer(minLength: 12)

                    Image(systemName: block.isEnabled ? "checkmark.circle" : "pause.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(LocalizedStringKey(block.isEnabled ? "workflow.blockEnabled" : "workflow.blockDisabled")))

                    Text(verbatim: "#\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showsInlineParameters {
                    Toggle(
                        "workflow.blockEnabled",
                        isOn: Binding(
                            get: { block.isEnabled },
                            set: { project.setWorkflowBlockEnabled(id: block.id, isEnabled: $0) }
                        )
                    )
                    .accessibilityIdentifier("workflowBlockEnabled.\(block.id.uuidString)")

                    let visibleParameters = block.visibleParameters
                    if visibleParameters.isEmpty {
                        Text("workflow.noParameters")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(visibleParameters) { parameter in
                                EffectParameterEditor(parameter: parameter) { value in
                                    project.updateWorkflowBlockParameter(
                                        blockID: block.id,
                                        key: parameter.key,
                                        value: value
                                    )
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    iconButton(
                        titleKey: "workflow.moveUp",
                        systemImage: "chevron.up",
                        disabled: isFirst
                    ) {
                        project.moveWorkflowBlock(id: block.id, offset: -1)
                    }

                    iconButton(
                        titleKey: "workflow.moveDown",
                        systemImage: "chevron.down",
                        disabled: isLast
                    ) {
                        project.moveWorkflowBlock(id: block.id, offset: 1)
                    }

                    iconButton(
                        titleKey: "workflow.duplicate",
                        systemImage: "doc.on.doc"
                    ) {
                        project.duplicateWorkflowBlock(id: block.id)
                    }

                    iconButton(
                        titleKey: "workflow.delete",
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        project.deleteWorkflowBlock(id: block.id)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                project.selectWorkflowBlock(id: block.id)
            }

            if !isLast {
                Divider()
                    .padding(.vertical, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workflowBlock.\(block.id.uuidString)")
    }

    private func iconButton(
        titleKey: String,
        systemImage: String,
        role: ButtonRole? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .accessibilityLabel(Text(LocalizedStringKey(titleKey)))
    }
}
