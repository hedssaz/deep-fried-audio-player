//
//  AudioProjectViewModel.swift
//  Deep-Fried Audio Player
//
//  Created by hedssaz on 2026/5/13.
//

import Combine
import Foundation

enum AudioProjectMode: String, CaseIterable, Identifiable {
    case singleModule
    case workflow

    var id: Self { self }

    var localizationKey: String {
        switch self {
        case .singleModule:
            "mode.singleModule"
        case .workflow:
            "mode.workflow"
        }
    }
}

enum ProcessingState: Equatable {
    case empty
    case dirty
    case processing(progress: Double?)
    case ready
    case failed(message: String)
}

enum PlaybackState: Equatable {
    case stopped
    case playingOriginal
    case playingProcessed
}

@MainActor
final class AudioProjectViewModel: ObservableObject {
    @Published var mode: AudioProjectMode = .singleModule
    @Published var originalAudioBuffer: AudioBuffer?
    @Published var processedPreviewBuffer: AudioBuffer?
    @Published var selectedSingleModule = EffectBlock.defaultBlock(
        type: .sampleRateReduction,
        order: 0
    )
    @Published var currentWorkflow = Workflow(name: "workflow.untitled")
    @Published var processingState: ProcessingState = .empty
    @Published var playbackState: PlaybackState = .stopped
    @Published var modulePresets: [ModulePreset] = []
    @Published var selectedModulePresetID: ModulePreset.ID?
    @Published var modulePresetName = ""
    @Published var singleModuleStatusKey: String?

    let availableSingleModuleTypes = EffectType.firstRealEffectTypes

    private let renderer: WorkflowRenderer
    private let modulePresetStore: ModulePresetStore
    private var renderTask: Task<Void, Never>?
    private var activeRenderToken: UUID?

    init(
        renderer: WorkflowRenderer = WorkflowRenderer(),
        modulePresetStore: ModulePresetStore = ModulePresetStore()
    ) {
        self.renderer = renderer
        self.modulePresetStore = modulePresetStore
    }

    func generateSampleAudio() {
        do {
            originalAudioBuffer = try SampleAudioFactory.makeDevelopmentSample()
            processedPreviewBuffer = nil
            playbackState = .stopped
            scheduleSingleModulePreviewRender()
        } catch {
            processingState = .failed(message: error.localizedDescription)
        }
    }

    func selectSingleModuleType(_ type: EffectType) {
        selectedSingleModule = EffectBlock.defaultBlock(type: type, order: 0)
        selectedModulePresetID = nil
        modulePresetName = ""
        singleModuleStatusKey = nil
        scheduleSingleModulePreviewRender()
    }

    func updateSingleModuleParameter(key: String, value: EffectParameterValue) {
        guard let parameterIndex = selectedSingleModule.parameters.firstIndex(where: { $0.key == key }) else {
            return
        }

        selectedSingleModule.parameters[parameterIndex].value = value
        selectedSingleModule.presetName = nil
        selectedModulePresetID = nil
        singleModuleStatusKey = nil
        scheduleSingleModulePreviewRender()
    }

    func renderSingleModulePreview() async {
        renderTask?.cancel()
        renderTask = nil
        await renderSingleModulePreviewWithoutCancelling()
    }

    func refreshModulePresets() async {
        do {
            modulePresets = try await modulePresetStore.loadAll()
            if let selectedModulePresetID,
               !modulePresets.contains(where: { $0.id == selectedModulePresetID }) {
                self.selectedModulePresetID = nil
            }
        } catch {
            singleModuleStatusKey = "singleModule.presetLoadFailed"
            processingState = .failed(message: error.localizedDescription)
        }
    }

    @discardableResult
    func saveCurrentModulePreset() async -> Bool {
        let trimmedName = modulePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            singleModuleStatusKey = "singleModule.presetNameRequired"
            return false
        }

        do {
            let now = Date()
            let existingPreset = selectedModulePresetID.flatMap { id in
                modulePresets.first { $0.id == id }
            }
            var block = selectedSingleModule
            block.presetName = trimmedName

            let preset = ModulePreset(
                id: existingPreset?.id ?? UUID(),
                name: trimmedName,
                block: block,
                createdAt: existingPreset?.createdAt ?? now,
                updatedAt: now
            )

            try await modulePresetStore.save(preset)
            modulePresets = try await modulePresetStore.loadAll()
            selectedModulePresetID = preset.id
            selectedSingleModule = block
            modulePresetName = trimmedName
            singleModuleStatusKey = "singleModule.presetSaved"
            return true
        } catch {
            singleModuleStatusKey = "singleModule.presetSaveFailed"
            processingState = .failed(message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func loadSelectedModulePreset() async -> Bool {
        guard let selectedModulePresetID else {
            singleModuleStatusKey = "singleModule.presetLoadFailed"
            return false
        }

        do {
            let preset = try await modulePresetStore.load(id: selectedModulePresetID)
            selectedSingleModule = preset.block
            selectedSingleModule.order = 0
            selectedSingleModule.presetName = preset.name
            modulePresetName = preset.name
            singleModuleStatusKey = "singleModule.presetLoaded"
            scheduleSingleModulePreviewRender()
            return true
        } catch {
            singleModuleStatusKey = "singleModule.presetLoadFailed"
            processingState = .failed(message: error.localizedDescription)
            return false
        }
    }

    func sendSingleModuleToWorkflow() {
        var workflowBlock = selectedSingleModule
        workflowBlock.id = UUID()
        workflowBlock.order = (currentWorkflow.blocks.map(\.order).max() ?? -1) + 1

        currentWorkflow.blocks.append(workflowBlock)
        currentWorkflow.updatedAt = Date()
        mode = .workflow
        singleModuleStatusKey = "singleModule.sentToWorkflow"
    }

    private func scheduleSingleModulePreviewRender() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            await self?.renderSingleModulePreviewWithoutCancelling()
        }
    }

    private func renderSingleModulePreviewWithoutCancelling() async {
        guard !Task.isCancelled else {
            return
        }

        guard let originalAudioBuffer else {
            processedPreviewBuffer = nil
            processingState = .empty
            return
        }

        let token = UUID()
        activeRenderToken = token
        processingState = .processing(progress: nil)

        let workflow = Workflow(
            name: "workflow.singleModulePreview",
            blocks: [selectedSingleModule]
        )

        do {
            let output = try await renderer.render(originalAudioBuffer, workflow: workflow)
            guard activeRenderToken == token, !Task.isCancelled else {
                return
            }

            processedPreviewBuffer = output
            processingState = .ready
        } catch is CancellationError {
            guard activeRenderToken == token else {
                return
            }

            processingState = .dirty
        } catch {
            guard activeRenderToken == token else {
                return
            }

            processedPreviewBuffer = nil
            processingState = .failed(message: error.localizedDescription)
            singleModuleStatusKey = "singleModule.renderFailed"
        }
    }
}
