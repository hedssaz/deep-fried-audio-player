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
    @Published var mode: AudioProjectMode = .singleModule {
        didSet {
            guard oldValue != mode else {
                return
            }

            schedulePreviewRenderForCurrentMode()
        }
    }
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
    @Published var selectedWorkflowModuleType: EffectType = .sampleRateReduction
    @Published var workflowPresets: [WorkflowPreset] = []
    @Published var selectedWorkflowPresetID: WorkflowPreset.ID?
    @Published var workflowPresetName = ""
    @Published var workflowStatusKey: String?
    @Published var isRecording = false
    @Published var audioSourceStatusKey: String?
    @Published var playbackStatusKey: String?

    let availableSingleModuleTypes = EffectType.availableUserFacingEffectTypes
    let availableWorkflowModuleTypes = EffectType.availableUserFacingEffectTypes

    private let renderer: WorkflowRenderer
    private let modulePresetStore: ModulePresetStore
    private let workflowPresetStore: WorkflowPresetStore
    private let audioImportService: any AudioImportServicing
    private let recordingService: any RecordingServicing
    private let playbackController: any AudioPlaybackControlling
    private var renderTask: Task<Void, Never>?
    private var activeRenderToken: UUID?
    private var activePlaybackToken: UUID?

    init(
        renderer: WorkflowRenderer = WorkflowRenderer(),
        modulePresetStore: ModulePresetStore = ModulePresetStore(),
        workflowPresetStore: WorkflowPresetStore = WorkflowPresetStore(),
        audioImportService: any AudioImportServicing = AudioImportService(),
        recordingService: (any RecordingServicing)? = nil,
        playbackController: (any AudioPlaybackControlling)? = nil
    ) {
        self.renderer = renderer
        self.modulePresetStore = modulePresetStore
        self.workflowPresetStore = workflowPresetStore
        self.audioImportService = audioImportService
        self.recordingService = recordingService ?? RecordingService(importService: audioImportService)
        self.playbackController = playbackController ?? AudioPlaybackController()
    }

    func generateSampleAudio() {
        do {
            loadAudioBuffer(
                try SampleAudioFactory.makeDevelopmentSample(),
                statusKey: nil
            )
        } catch {
            processingState = .failed(message: error.localizedDescription)
        }
    }

    func importAudio(from url: URL) async {
        stopCurrentPlayback(clearStatus: true)
        audioSourceStatusKey = "audio.importing"
        isRecording = false

        do {
            let buffer = try await audioImportService.importAudio(from: url)
            loadAudioBuffer(
                buffer,
                statusKey: "audio.imported",
                shouldStopPlayback: false
            )
        } catch {
            audioSourceStatusKey = "audio.importFailed"
            processedPreviewBuffer = nil
            processingState = .failed(message: error.localizedDescription)
        }
    }

    func startRecording() async {
        guard !isRecording else {
            return
        }

        stopCurrentPlayback(clearStatus: true)
        audioSourceStatusKey = "audio.recording"

        do {
            try await recordingService.startRecording()
            isRecording = true
        } catch RecordingServiceError.permissionDenied {
            isRecording = false
            audioSourceStatusKey = "audio.recordPermissionDenied"
            processingState = originalAudioBuffer == nil ? .empty : .dirty
        } catch {
            isRecording = false
            audioSourceStatusKey = "audio.recordFailed"
            processingState = .failed(message: error.localizedDescription)
        }
    }

    func playOriginalAudio() async {
        guard let originalAudioBuffer else {
            stopCurrentPlayback(clearStatus: false)
            playbackStatusKey = "playback.noOriginal"
            return
        }

        await playAudioBuffer(
            originalAudioBuffer,
            playbackState: .playingOriginal,
            statusKey: "playback.playingOriginal"
        )
    }

    func playProcessedAudio() async {
        guard let processedPreviewBuffer else {
            stopCurrentPlayback(clearStatus: false)
            playbackStatusKey = "playback.noProcessed"
            return
        }

        await playAudioBuffer(
            processedPreviewBuffer,
            playbackState: .playingProcessed,
            statusKey: "playback.playingProcessed"
        )
    }

    func stopPlayback() {
        stopCurrentPlayback(clearStatus: true)
    }

    func stopRecording() async {
        guard isRecording else {
            return
        }

        audioSourceStatusKey = "audio.processingRecording"

        do {
            let buffer = try await recordingService.stopRecording()
            isRecording = false
            loadAudioBuffer(buffer, statusKey: "audio.recorded")
        } catch {
            isRecording = false
            audioSourceStatusKey = "audio.recordFailed"
            processedPreviewBuffer = nil
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

    func renderWorkflowPreview() async {
        renderTask?.cancel()
        renderTask = nil
        await renderWorkflowPreviewWithoutCancelling()
    }

    func refreshPresets() async {
        await refreshModulePresets()
        await refreshWorkflowPresets()
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

    func refreshWorkflowPresets() async {
        do {
            workflowPresets = try await workflowPresetStore.loadAll()
            if let selectedWorkflowPresetID,
               !workflowPresets.contains(where: { $0.id == selectedWorkflowPresetID }) {
                self.selectedWorkflowPresetID = nil
            }
        } catch {
            workflowStatusKey = "workflow.presetLoadFailed"
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

    @discardableResult
    func saveCurrentWorkflowPreset() async -> Bool {
        let trimmedName = workflowPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            workflowStatusKey = "workflow.presetNameRequired"
            return false
        }

        do {
            let now = Date()
            let existingPreset = selectedWorkflowPresetID.flatMap { id in
                workflowPresets.first { $0.id == id }
            }
            var workflow = currentWorkflow
            workflow.name = trimmedName
            workflow.updatedAt = now

            let preset = WorkflowPreset(
                id: existingPreset?.id ?? UUID(),
                name: trimmedName,
                workflow: workflow,
                createdAt: existingPreset?.createdAt ?? now,
                updatedAt: now
            )

            try await workflowPresetStore.save(preset)
            workflowPresets = try await workflowPresetStore.loadAll()
            selectedWorkflowPresetID = preset.id
            currentWorkflow = workflow
            workflowPresetName = trimmedName
            workflowStatusKey = "workflow.presetSaved"
            return true
        } catch {
            workflowStatusKey = "workflow.presetSaveFailed"
            processingState = .failed(message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func loadSelectedWorkflowPreset() async -> Bool {
        guard let selectedWorkflowPresetID else {
            workflowStatusKey = "workflow.presetLoadFailed"
            return false
        }

        do {
            let preset = try await workflowPresetStore.load(id: selectedWorkflowPresetID)
            currentWorkflow = preset.workflow
            normalizeWorkflowOrder()
            workflowPresetName = preset.name
            workflowStatusKey = "workflow.presetLoaded"
            scheduleWorkflowPreviewRender()
            return true
        } catch {
            workflowStatusKey = "workflow.presetLoadFailed"
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
        workflowStatusKey = "workflow.moduleReceived"
        scheduleWorkflowPreviewRender()
    }

    func addWorkflowBlock(type: EffectType? = nil) {
        let blockType = type ?? selectedWorkflowModuleType
        let block = EffectBlock.defaultBlock(
            type: blockType,
            order: nextWorkflowOrder()
        )

        currentWorkflow.blocks.append(block)
        markWorkflowChanged()
    }

    func duplicateWorkflowBlock(id: EffectBlock.ID) {
        guard let originalBlock = currentWorkflow.blocks.first(where: { $0.id == id }) else {
            return
        }

        var duplicatedBlock = originalBlock
        duplicatedBlock.id = UUID()
        duplicatedBlock.order = nextWorkflowOrder()
        currentWorkflow.blocks.append(duplicatedBlock)
        markWorkflowChanged()
    }

    func deleteWorkflowBlock(id: EffectBlock.ID) {
        let originalCount = currentWorkflow.blocks.count
        currentWorkflow.blocks.removeAll { $0.id == id }

        guard currentWorkflow.blocks.count != originalCount else {
            return
        }

        normalizeWorkflowOrder()
        markWorkflowChanged()
    }

    func setWorkflowBlockEnabled(id: EffectBlock.ID, isEnabled: Bool) {
        guard let blockIndex = currentWorkflow.blocks.firstIndex(where: { $0.id == id }),
              currentWorkflow.blocks[blockIndex].isEnabled != isEnabled else {
            return
        }

        currentWorkflow.blocks[blockIndex].isEnabled = isEnabled
        markWorkflowChanged()
    }

    func updateWorkflowBlockParameter(
        blockID: EffectBlock.ID,
        key: String,
        value: EffectParameterValue
    ) {
        guard let blockIndex = currentWorkflow.blocks.firstIndex(where: { $0.id == blockID }),
              let parameterIndex = currentWorkflow.blocks[blockIndex].parameters.firstIndex(where: { $0.key == key }) else {
            return
        }

        currentWorkflow.blocks[blockIndex].parameters[parameterIndex].value = value
        currentWorkflow.blocks[blockIndex].presetName = nil
        markWorkflowChanged()
    }

    func moveWorkflowBlocks(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else {
            return
        }

        let orderedBlocks = currentWorkflow.orderedBlocks
        let validSource = IndexSet(source.filter { orderedBlocks.indices.contains($0) })
        guard !validSource.isEmpty else {
            return
        }

        let boundedDestination = min(max(destination, 0), orderedBlocks.count)
        currentWorkflow.blocks = Self.reorderedBlocks(
            orderedBlocks,
            fromOffsets: validSource,
            toOffset: boundedDestination
        )
        renumberWorkflowBlocksInCurrentOrder()
        markWorkflowChanged()
    }

    func moveWorkflowBlock(id: EffectBlock.ID, offset: Int) {
        guard offset != 0,
              let sourceIndex = currentWorkflow.orderedBlocks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let destinationIndex = sourceIndex + offset
        guard currentWorkflow.orderedBlocks.indices.contains(destinationIndex) else {
            return
        }

        currentWorkflow.blocks = currentWorkflow.orderedBlocks
        currentWorkflow.blocks.swapAt(sourceIndex, destinationIndex)
        renumberWorkflowBlocksInCurrentOrder()
        markWorkflowChanged()
    }

    private func schedulePreviewRenderForCurrentMode() {
        switch mode {
        case .singleModule:
            scheduleSingleModulePreviewRender()
        case .workflow:
            scheduleWorkflowPreviewRender()
        }
    }

    private func scheduleSingleModulePreviewRender() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            await self?.renderSingleModulePreviewWithoutCancelling()
        }
    }

    private func scheduleWorkflowPreviewRender() {
        guard mode == .workflow else {
            return
        }

        renderTask?.cancel()
        renderTask = Task { [weak self] in
            await self?.renderWorkflowPreviewWithoutCancelling()
        }
    }

    private func markWorkflowChanged() {
        currentWorkflow.updatedAt = Date()
        workflowStatusKey = nil
        selectedWorkflowPresetID = nil
        scheduleWorkflowPreviewRender()
    }

    private func nextWorkflowOrder() -> Int {
        (currentWorkflow.blocks.map(\.order).max() ?? -1) + 1
    }

    private func normalizeWorkflowOrder() {
        currentWorkflow.blocks = currentWorkflow.orderedBlocks.enumerated().map { index, block in
            var normalizedBlock = block
            normalizedBlock.order = index
            return normalizedBlock
        }
    }

    private func renumberWorkflowBlocksInCurrentOrder() {
        currentWorkflow.blocks = currentWorkflow.blocks.enumerated().map { index, block in
            var normalizedBlock = block
            normalizedBlock.order = index
            return normalizedBlock
        }
    }

    private nonisolated static func reorderedBlocks(
        _ blocks: [EffectBlock],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [EffectBlock] {
        var result = blocks
        let movingBlocks = source.sorted().map { result[$0] }

        for index in source.sorted(by: >) {
            result.remove(at: index)
        }

        let removedBeforeDestination = source.filter { $0 < destination }.count
        let adjustedDestination = min(
            max(destination - removedBeforeDestination, 0),
            result.count
        )
        result.insert(contentsOf: movingBlocks, at: adjustedDestination)
        return result
    }

    private func loadAudioBuffer(
        _ buffer: AudioBuffer,
        statusKey: String?,
        shouldStopPlayback: Bool = true
    ) {
        if shouldStopPlayback {
            stopCurrentPlayback(clearStatus: true)
        }

        originalAudioBuffer = buffer
        processedPreviewBuffer = nil
        audioSourceStatusKey = statusKey
        schedulePreviewRenderForCurrentMode()
    }

    private func playAudioBuffer(
        _ buffer: AudioBuffer,
        playbackState targetPlaybackState: PlaybackState,
        statusKey: String
    ) async {
        guard !isRecording else {
            stopCurrentPlayback(clearStatus: false)
            playbackStatusKey = "playback.unavailableWhileRecording"
            return
        }

        let playbackToken = UUID()
        activePlaybackToken = playbackToken
        playbackState = targetPlaybackState
        playbackStatusKey = statusKey

        do {
            try await playbackController.play(buffer) { [weak self] in
                guard let self, self.activePlaybackToken == playbackToken else {
                    return
                }

                self.playbackState = .stopped
                self.activePlaybackToken = nil
                self.playbackStatusKey = nil
            }
        } catch {
            stopCurrentPlayback(clearStatus: false)
            playbackStatusKey = "playback.failed"
        }
    }

    private func stopCurrentPlayback(clearStatus: Bool) {
        activePlaybackToken = nil
        playbackController.stop()
        playbackState = .stopped

        if clearStatus {
            playbackStatusKey = nil
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

    private func renderWorkflowPreviewWithoutCancelling() async {
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

        do {
            let output = try await renderer.render(originalAudioBuffer, workflow: currentWorkflow)
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
            workflowStatusKey = "workflow.renderFailed"
        }
    }
}
