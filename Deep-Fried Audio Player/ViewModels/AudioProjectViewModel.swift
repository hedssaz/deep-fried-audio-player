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

enum OperationProgressKind: Equatable {
    case singleModulePreview
    case workflowPreview
    case audioImport
    case recording
    case playback
}

enum OperationProgressTerminalState: Equatable {
    case completed
    case cancelled
    case failed

    var labelKey: String {
        switch self {
        case .completed:
            "progress.status.completed"
        case .cancelled:
            "progress.status.cancelled"
        case .failed:
            "progress.status.failed"
        }
    }
}

enum OperationProgressAction: Equatable {
    case stop
    case cancel

    var titleKey: String {
        switch self {
        case .stop:
            "progress.action.stop"
        case .cancel:
            "progress.action.cancel"
        }
    }

    var systemImage: String {
        switch self {
        case .stop:
            "stop.fill"
        case .cancel:
            "xmark"
        }
    }
}

enum OperationProgressStep: Equatable {
    case block(current: Int, total: Int)

    var localizationKey: String {
        switch self {
        case .block:
            "progress.step.block"
        }
    }

    var currentValue: Int {
        switch self {
        case let .block(current, _):
            current
        }
    }

    var totalValue: Int {
        switch self {
        case let .block(_, total):
            total
        }
    }
}

struct OperationProgress: Equatable {
    var kind: OperationProgressKind
    var titleKey: String
    var phaseKey: String
    var progress: Double?
    var step: OperationProgressStep?
    var itemKey: String?
    var elapsedStartDate: Date?
    var terminalState: OperationProgressTerminalState?
    var action: OperationProgressAction?

    var isActive: Bool {
        terminalState == nil
    }
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
    @Published var selectedWorkflowBlockID: EffectBlock.ID?
    @Published var isRecording = false
    @Published var audioSourceStatusKey: String?
    @Published var playbackStatusKey: String?
    @Published var operationProgress: OperationProgress?

    let availableSingleModuleTypes = EffectType.availableUserFacingEffectTypes
    let availableWorkflowModuleTypes = EffectType.availableUserFacingEffectTypes

    var selectedWorkflowBlock: EffectBlock? {
        guard let selectedWorkflowBlockID else {
            return nil
        }

        return currentWorkflow.orderedBlocks.first { $0.id == selectedWorkflowBlockID }
    }

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
        operationProgress = OperationProgress(
            kind: .audioImport,
            titleKey: "progress.import.title",
            phaseKey: "progress.phase.decodingAudio",
            progress: nil,
            action: nil
        )

        do {
            let buffer = try await audioImportService.importAudio(from: url)
            markOperationCompleted(phaseKey: "progress.phase.completed")
            loadAudioBuffer(
                buffer,
                statusKey: "audio.imported",
                shouldStopPlayback: false
            )
        } catch {
            audioSourceStatusKey = "audio.importFailed"
            processedPreviewBuffer = nil
            processingState = .failed(message: error.localizedDescription)
            markOperationFailed()
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
            operationProgress = OperationProgress(
                kind: .recording,
                titleKey: "progress.recording.title",
                phaseKey: "progress.phase.recording",
                progress: nil,
                elapsedStartDate: Date(),
                action: .cancel
            )
        } catch RecordingServiceError.permissionDenied {
            isRecording = false
            audioSourceStatusKey = "audio.recordPermissionDenied"
            processingState = originalAudioBuffer == nil ? .empty : .dirty
            operationProgress = nil
        } catch {
            isRecording = false
            audioSourceStatusKey = "audio.recordFailed"
            processingState = .failed(message: error.localizedDescription)
            operationProgress = OperationProgress(
                kind: .recording,
                titleKey: "progress.recording.title",
                phaseKey: "progress.phase.failed",
                progress: nil,
                terminalState: .failed,
                action: nil
            )
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
        operationProgress = OperationProgress(
            kind: .recording,
            titleKey: "progress.recording.title",
            phaseKey: "progress.phase.processingRecording",
            progress: nil,
            action: nil
        )

        do {
            let buffer = try await recordingService.stopRecording()
            isRecording = false
            markOperationCompleted(phaseKey: "progress.phase.completed")
            loadAudioBuffer(buffer, statusKey: "audio.recorded")
        } catch {
            isRecording = false
            audioSourceStatusKey = "audio.recordFailed"
            processedPreviewBuffer = nil
            processingState = .failed(message: error.localizedDescription)
            markOperationFailed()
        }
    }

    func cancelActiveOperation() async {
        guard let operationProgress else {
            return
        }

        switch operationProgress.kind {
        case .singleModulePreview, .workflowPreview:
            await cancelPreviewRender()
        case .recording:
            await cancelRecording()
        case .playback:
            stopPlayback()
        case .audioImport:
            break
        }
    }

    func cancelRecording() async {
        guard isRecording else {
            return
        }

        await recordingService.cancelRecording()
        isRecording = false
        audioSourceStatusKey = "audio.recordCancelled"
        operationProgress = OperationProgress(
            kind: .recording,
            titleKey: "progress.recording.title",
            phaseKey: "progress.phase.cancelled",
            progress: nil,
            terminalState: .cancelled,
            action: nil
        )
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
            self.selectedWorkflowBlockID = currentWorkflow.orderedBlocks.first?.id
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
        selectedWorkflowBlockID = workflowBlock.id
        currentWorkflow.updatedAt = Date()
        mode = .workflow
        singleModuleStatusKey = "singleModule.sentToWorkflow"
        workflowStatusKey = "workflow.moduleReceived"
        scheduleWorkflowPreviewRender()
    }

    func selectWorkflowBlock(id: EffectBlock.ID?) {
        guard let id else {
            selectedWorkflowBlockID = nil
            return
        }

        guard currentWorkflow.blocks.contains(where: { $0.id == id }) else {
            return
        }

        selectedWorkflowBlockID = id
    }

    func addWorkflowBlock(type: EffectType? = nil) {
        let blockType = type ?? selectedWorkflowModuleType
        let block = EffectBlock.defaultBlock(
            type: blockType,
            order: nextWorkflowOrder()
        )

        currentWorkflow.blocks.append(block)
        selectedWorkflowBlockID = block.id
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
        selectedWorkflowBlockID = duplicatedBlock.id
        markWorkflowChanged()
    }

    func deleteWorkflowBlock(id: EffectBlock.ID) {
        let orderedBlocks = currentWorkflow.orderedBlocks
        guard let deletedOrderedIndex = orderedBlocks.firstIndex(where: { $0.id == id }) else {
            return
        }

        currentWorkflow.blocks.removeAll { $0.id == id }
        normalizeWorkflowOrder()

        if selectedWorkflowBlockID == id {
            selectedWorkflowBlockID = nearestWorkflowBlockID(afterDeletingOrderedIndex: deletedOrderedIndex)
        } else if let selectedWorkflowBlockID,
                  !currentWorkflow.blocks.contains(where: { $0.id == selectedWorkflowBlockID }) {
            self.selectedWorkflowBlockID = currentWorkflow.orderedBlocks.first?.id
        }

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

    private func nearestWorkflowBlockID(afterDeletingOrderedIndex deletedOrderedIndex: Int) -> EffectBlock.ID? {
        let orderedBlocks = currentWorkflow.orderedBlocks
        guard !orderedBlocks.isEmpty else {
            return nil
        }

        let fallbackIndex = min(deletedOrderedIndex, orderedBlocks.count - 1)
        return orderedBlocks[fallbackIndex].id
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
        operationProgress = OperationProgress(
            kind: .playback,
            titleKey: "progress.playback.title",
            phaseKey: statusKey,
            progress: nil,
            action: .stop
        )

        do {
            try await playbackController.play(buffer) { [weak self] in
                guard let self, self.activePlaybackToken == playbackToken else {
                    return
                }

                self.playbackState = .stopped
                self.activePlaybackToken = nil
                self.playbackStatusKey = nil
                self.clearPlaybackProgressIfNeeded()
            }
        } catch {
            stopCurrentPlayback(clearStatus: false)
            playbackStatusKey = "playback.failed"
            operationProgress = OperationProgress(
                kind: .playback,
                titleKey: "progress.playback.title",
                phaseKey: "progress.phase.failed",
                progress: nil,
                terminalState: .failed,
                action: nil
            )
        }
    }

    private func stopCurrentPlayback(clearStatus: Bool) {
        activePlaybackToken = nil
        playbackController.stop()
        playbackState = .stopped

        if clearStatus {
            playbackStatusKey = nil
        }

        clearPlaybackProgressIfNeeded()
    }

    private func clearPlaybackProgressIfNeeded() {
        guard operationProgress?.kind == .playback else {
            return
        }

        operationProgress = nil
    }

    private func markOperationCompleted(phaseKey: String) {
        guard var progress = operationProgress else {
            return
        }

        progress.phaseKey = phaseKey
        progress.progress = progress.progress == nil ? nil : 1
        progress.elapsedStartDate = nil
        progress.terminalState = .completed
        progress.action = nil
        operationProgress = progress
    }

    private func markOperationCancelled() {
        guard var progress = operationProgress else {
            return
        }

        progress.phaseKey = "progress.phase.cancelled"
        progress.elapsedStartDate = nil
        progress.terminalState = .cancelled
        progress.action = nil
        operationProgress = progress
    }

    private func markOperationFailed() {
        guard var progress = operationProgress else {
            return
        }

        progress.phaseKey = "progress.phase.failed"
        progress.elapsedStartDate = nil
        progress.terminalState = .failed
        progress.action = nil
        operationProgress = progress
    }

    private func cancelPreviewRender() async {
        guard operationProgress?.kind == .singleModulePreview
                || operationProgress?.kind == .workflowPreview else {
            return
        }

        activeRenderToken = nil
        renderTask?.cancel()
        renderTask = nil
        await renderer.cancelActiveRender()
        processingState = originalAudioBuffer == nil ? .empty : .dirty
        markOperationCancelled()
    }

    private func renderProgressHandler(
        token: UUID,
        kind: OperationProgressKind,
        titleKey: String
    ) -> @Sendable (WorkflowRenderProgress) -> Void {
        { [weak self] renderProgress in
            Task { @MainActor [weak self] in
                self?.handleRenderProgress(
                    renderProgress,
                    token: token,
                    kind: kind,
                    titleKey: titleKey
                )
            }
        }
    }

    private func handleRenderProgress(
        _ renderProgress: WorkflowRenderProgress,
        token: UUID,
        kind: OperationProgressKind,
        titleKey: String
    ) {
        guard activeRenderToken == token,
              !Task.isCancelled else {
            return
        }

        let progressValue = renderProgress.progress.clamped(to: 0...1)
        processingState = .processing(progress: progressValue)

        operationProgress = OperationProgress(
            kind: kind,
            titleKey: titleKey,
            phaseKey: phaseKey(for: renderProgress.phase, kind: kind),
            progress: progressValue,
            step: step(for: renderProgress, kind: kind),
            itemKey: itemKey(for: renderProgress, kind: kind),
            action: .stop
        )
    }

    private func phaseKey(
        for phase: WorkflowRenderProgress.Phase,
        kind: OperationProgressKind
    ) -> String {
        switch phase {
        case .preparing:
            kind == .singleModulePreview
                ? "progress.phase.renderingModule"
                : "progress.phase.renderingWorkflow"
        case .processingBlock:
            kind == .singleModulePreview
                ? "progress.phase.renderingModule"
                : "progress.phase.renderingBlock"
        case .codecPreparing:
            "progress.phase.preparing"
        case .codecEncoding:
            "progress.phase.encoding"
        case .codecDecoding:
            "progress.phase.decoding"
        case .codecFinalizing:
            "progress.phase.finalizing"
        case .finalizing:
            "progress.phase.finalizing"
        case .completed:
            "progress.phase.completed"
        }
    }

    private func step(
        for renderProgress: WorkflowRenderProgress,
        kind: OperationProgressKind
    ) -> OperationProgressStep? {
        guard kind == .workflowPreview,
              let currentBlockIndex = renderProgress.currentBlockIndex,
              renderProgress.totalBlockCount > 0 else {
            return nil
        }

        return .block(
            current: currentBlockIndex + 1,
            total: renderProgress.totalBlockCount
        )
    }

    private func itemKey(
        for renderProgress: WorkflowRenderProgress,
        kind: OperationProgressKind
    ) -> String? {
        switch kind {
        case .singleModulePreview:
            renderProgress.currentBlock?.name ?? selectedSingleModule.name
        case .workflowPreview:
            renderProgress.currentBlock?.name
        case .audioImport, .recording, .playback:
            nil
        }
    }

    private func renderSingleModulePreviewWithoutCancelling() async {
        guard !Task.isCancelled else {
            return
        }

        guard let originalAudioBuffer else {
            processedPreviewBuffer = nil
            processingState = .empty
            operationProgress = nil
            return
        }

        let token = UUID()
        activeRenderToken = token
        processingState = .processing(progress: 0)
        operationProgress = OperationProgress(
            kind: .singleModulePreview,
            titleKey: "progress.preview.single.title",
            phaseKey: "progress.phase.renderingModule",
            progress: 0,
            itemKey: selectedSingleModule.name,
            action: .stop
        )

        let workflow = Workflow(
            name: "workflow.singleModulePreview",
            blocks: [selectedSingleModule]
        )

        do {
            let output = try await renderer.render(
                originalAudioBuffer,
                workflow: workflow,
                progress: renderProgressHandler(
                    token: token,
                    kind: .singleModulePreview,
                    titleKey: "progress.preview.single.title"
                )
            )
            guard activeRenderToken == token, !Task.isCancelled else {
                return
            }

            processedPreviewBuffer = output
            processingState = .ready
            markOperationCompleted(phaseKey: "progress.phase.completed")
        } catch is CancellationError {
            guard activeRenderToken == token else {
                return
            }

            processingState = .dirty
            markOperationCancelled()
        } catch {
            guard activeRenderToken == token else {
                return
            }

            processedPreviewBuffer = nil
            processingState = .failed(message: error.localizedDescription)
            singleModuleStatusKey = "singleModule.renderFailed"
            markOperationFailed()
        }
    }

    private func renderWorkflowPreviewWithoutCancelling() async {
        guard !Task.isCancelled else {
            return
        }

        guard let originalAudioBuffer else {
            processedPreviewBuffer = nil
            processingState = .empty
            operationProgress = nil
            return
        }

        let token = UUID()
        activeRenderToken = token
        processingState = .processing(progress: 0)
        operationProgress = OperationProgress(
            kind: .workflowPreview,
            titleKey: "progress.preview.workflow.title",
            phaseKey: "progress.phase.renderingWorkflow",
            progress: 0,
            action: .stop
        )

        do {
            let output = try await renderer.render(
                originalAudioBuffer,
                workflow: currentWorkflow,
                progress: renderProgressHandler(
                    token: token,
                    kind: .workflowPreview,
                    titleKey: "progress.preview.workflow.title"
                )
            )
            guard activeRenderToken == token, !Task.isCancelled else {
                return
            }

            processedPreviewBuffer = output
            processingState = .ready
            markOperationCompleted(phaseKey: "progress.phase.completed")
        } catch is CancellationError {
            guard activeRenderToken == token else {
                return
            }

            processingState = .dirty
            markOperationCancelled()
        } catch {
            guard activeRenderToken == token else {
                return
            }

            processedPreviewBuffer = nil
            processingState = .failed(message: error.localizedDescription)
            workflowStatusKey = "workflow.renderFailed"
            markOperationFailed()
        }
    }
}
