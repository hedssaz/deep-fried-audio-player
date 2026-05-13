//
//  WorkflowModeTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import XCTest
@testable import Deep_Fried_Audio_Player

@MainActor
final class WorkflowModeTests: XCTestCase {
    func testAddingWorkflowBlocksAssignsSequentialOrder() {
        let project = makeProject()

        project.addWorkflowBlock(type: .sampleRateReduction)
        project.addWorkflowBlock(type: .clipping)
        project.addWorkflowBlock(type: .limiter)

        XCTAssertEqual(
            project.currentWorkflow.orderedBlocks.map(\.type),
            [.sampleRateReduction, .clipping, .limiter]
        )
        XCTAssertEqual(project.currentWorkflow.orderedBlocks.map(\.order), [0, 1, 2])
    }

    func testDuplicatingWorkflowBlockCreatesNewIDAndAppendsNextOrder() throws {
        let project = makeProject()
        project.addWorkflowBlock(type: .bitDepthReduction)
        let originalBlock = try XCTUnwrap(project.currentWorkflow.orderedBlocks.first)

        project.duplicateWorkflowBlock(id: originalBlock.id)

        let blocks = project.currentWorkflow.orderedBlocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].type, originalBlock.type)
        XCTAssertEqual(blocks[1].parameters, originalBlock.parameters)
        XCTAssertEqual(blocks[1].order, 1)
        XCTAssertNotEqual(blocks[1].id, originalBlock.id)
    }

    func testDeletingWorkflowBlockNormalizesRemainingOrder() throws {
        let project = makeProject()
        project.addWorkflowBlock(type: .sampleRateReduction)
        project.addWorkflowBlock(type: .clipping)
        project.addWorkflowBlock(type: .limiter)
        let deletedBlock = try XCTUnwrap(project.currentWorkflow.orderedBlocks.dropFirst().first)

        project.deleteWorkflowBlock(id: deletedBlock.id)

        XCTAssertEqual(
            project.currentWorkflow.orderedBlocks.map(\.type),
            [.sampleRateReduction, .limiter]
        )
        XCTAssertEqual(project.currentWorkflow.orderedBlocks.map(\.order), [0, 1])
    }

    func testMovingWorkflowBlocksChangesOrderedExecutionSequence() {
        let project = makeProject()
        project.addWorkflowBlock(type: .sampleRateReduction)
        project.addWorkflowBlock(type: .clipping)
        project.addWorkflowBlock(type: .limiter)

        project.moveWorkflowBlocks(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(
            project.currentWorkflow.orderedBlocks.map(\.type),
            [.limiter, .sampleRateReduction, .clipping]
        )
        XCTAssertEqual(project.currentWorkflow.orderedBlocks.map(\.order), [0, 1, 2])
    }

    func testAddingWorkflowBlockSelectsNewBlock() throws {
        let project = makeProject()

        project.addWorkflowBlock(type: .sampleRateReduction)
        let firstBlock = try XCTUnwrap(project.currentWorkflow.orderedBlocks.first)

        XCTAssertEqual(project.selectedWorkflowBlockID, firstBlock.id)
        XCTAssertEqual(project.selectedWorkflowBlock, firstBlock)
    }

    func testDuplicatingWorkflowBlockSelectsDuplicate() throws {
        let project = makeProject()
        project.addWorkflowBlock(type: .bitDepthReduction)
        let originalBlock = try XCTUnwrap(project.currentWorkflow.orderedBlocks.first)

        project.duplicateWorkflowBlock(id: originalBlock.id)

        let duplicatedBlock = try XCTUnwrap(project.currentWorkflow.orderedBlocks.last)
        XCTAssertEqual(project.selectedWorkflowBlockID, duplicatedBlock.id)
        XCTAssertNotEqual(project.selectedWorkflowBlockID, originalBlock.id)
    }

    func testMovingWorkflowBlocksPreservesSelectedBlock() throws {
        let project = makeProject()
        project.addWorkflowBlock(type: .sampleRateReduction)
        project.addWorkflowBlock(type: .clipping)
        project.addWorkflowBlock(type: .limiter)
        let selectedBlock = try XCTUnwrap(project.currentWorkflow.orderedBlocks.dropFirst().first)
        project.selectWorkflowBlock(id: selectedBlock.id)

        project.moveWorkflowBlocks(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(project.selectedWorkflowBlockID, selectedBlock.id)
        XCTAssertEqual(project.selectedWorkflowBlock?.type, .clipping)
    }

    func testDeletingSelectedWorkflowBlockSelectsNearestRemainingBlock() throws {
        let project = makeProject()
        project.addWorkflowBlock(type: .sampleRateReduction)
        project.addWorkflowBlock(type: .clipping)
        project.addWorkflowBlock(type: .limiter)
        let orderedBlocks = project.currentWorkflow.orderedBlocks
        project.selectWorkflowBlock(id: orderedBlocks[1].id)

        project.deleteWorkflowBlock(id: orderedBlocks[1].id)

        let afterMiddleDelete = project.currentWorkflow.orderedBlocks
        XCTAssertEqual(project.selectedWorkflowBlockID, afterMiddleDelete[1].id)
        XCTAssertEqual(project.selectedWorkflowBlock?.type, .limiter)

        project.deleteWorkflowBlock(id: afterMiddleDelete[1].id)

        let afterLastDelete = project.currentWorkflow.orderedBlocks
        XCTAssertEqual(project.selectedWorkflowBlockID, afterLastDelete[0].id)
        XCTAssertEqual(project.selectedWorkflowBlock?.type, .sampleRateReduction)

        project.deleteWorkflowBlock(id: afterLastDelete[0].id)

        XCTAssertNil(project.selectedWorkflowBlockID)
        XCTAssertNil(project.selectedWorkflowBlock)
    }

    func testLoadingWorkflowPresetSelectsFirstOrderedBlock() async throws {
        let store = WorkflowPresetStore(directoryURL: makeTemporaryDirectory())
        let firstBlock = EffectBlock.defaultBlock(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            type: .clipping,
            order: 0
        )
        let secondBlock = EffectBlock.defaultBlock(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            type: .limiter,
            order: 1
        )
        let preset = WorkflowPreset(
            name: "Selection",
            workflow: Workflow(name: "Selection", blocks: [secondBlock, firstBlock])
        )
        try await store.save(preset)
        let project = AudioProjectViewModel(
            modulePresetStore: ModulePresetStore(directoryURL: makeTemporaryDirectory()),
            workflowPresetStore: store
        )
        project.selectedWorkflowPresetID = preset.id

        let didLoad = await project.loadSelectedWorkflowPreset()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(project.selectedWorkflowBlockID, firstBlock.id)
        XCTAssertEqual(project.selectedWorkflowBlock?.type, .clipping)
    }

    func testDisabledWorkflowBlockIsBypassedDuringPreviewRender() async throws {
        let project = makeProject()
        project.mode = .workflow
        project.addWorkflowBlock(type: .clipping)
        let blockID = try XCTUnwrap(project.currentWorkflow.orderedBlocks.first?.id)
        project.setWorkflowBlockEnabled(id: blockID, isEnabled: false)

        project.generateSampleAudio()
        await project.renderWorkflowPreview()

        let original = try XCTUnwrap(project.originalAudioBuffer)
        let processed = try XCTUnwrap(project.processedPreviewBuffer)

        XCTAssertEqual(project.processingState, .ready)
        XCTAssertEqual(processed, original)
        XCTAssertEqual(project.playbackState, .stopped)
    }

    func testWorkflowPresetStoreRoundTripsJSON() async throws {
        let store = WorkflowPresetStore(directoryURL: makeTemporaryDirectory())
        let workflow = Workflow(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Chain",
            blocks: [
                EffectBlock.defaultBlock(
                    id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                    type: .clipping,
                    order: 0
                ),
                EffectBlock.defaultBlock(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                    type: .limiter,
                    order: 1
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let preset = WorkflowPreset(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            name: "Chain",
            workflow: workflow,
            createdAt: Date(timeIntervalSince1970: 1_800_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_300)
        )

        try await store.save(preset)

        let loaded = try await store.load(id: preset.id)
        let allPresets = try await store.loadAll()

        XCTAssertEqual(loaded, preset)
        XCTAssertEqual(allPresets, [preset])
    }

    func testWorkflowParameterEditChangesPreviewAndKeepsFiniteSamples() async throws {
        let project = makeProject()
        project.mode = .workflow
        project.addWorkflowBlock(type: .clipping)
        project.generateSampleAudio()
        await project.renderWorkflowPreview()

        let firstOutput = try XCTUnwrap(project.processedPreviewBuffer)
        let blockID = try XCTUnwrap(project.currentWorkflow.orderedBlocks.first?.id)

        project.updateWorkflowBlockParameter(
            blockID: blockID,
            key: EffectParameterKey.threshold,
            value: .float(0.12)
        )
        await project.renderWorkflowPreview()

        let secondOutput = try XCTUnwrap(project.processedPreviewBuffer)
        let updatedBlock = try XCTUnwrap(project.currentWorkflow.orderedBlocks.first)
        let updatedParameter = try XCTUnwrap(
            updatedBlock.parameters.first { $0.key == EffectParameterKey.threshold }
        )

        XCTAssertEqual(updatedParameter.value, .float(0.12))
        XCTAssertNotEqual(firstOutput.samples, secondOutput.samples)
        XCTAssertTrue(secondOutput.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertEqual(secondOutput.frames, firstOutput.frames)
        XCTAssertEqual(project.playbackState, .stopped)
    }

    func testWorkflowChangesWaitForManualProcessing() async throws {
        let project = makeProject()
        project.mode = .workflow
        project.addWorkflowBlock(type: .clipping)
        project.generateSampleAudio()

        XCTAssertEqual(project.processingState, .dirty)
        XCTAssertNil(project.processedPreviewBuffer)

        await project.renderProcessedPreview()
        let firstOutput = try XCTUnwrap(project.processedPreviewBuffer)
        XCTAssertEqual(project.processingState, .ready)

        let blockID = try XCTUnwrap(project.currentWorkflow.orderedBlocks.first?.id)
        project.updateWorkflowBlockParameter(
            blockID: blockID,
            key: EffectParameterKey.threshold,
            value: .float(0.12)
        )

        XCTAssertEqual(project.processingState, .dirty)
        XCTAssertEqual(project.processedPreviewBuffer, firstOutput)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(project.processingState, .dirty)
        XCTAssertEqual(project.processedPreviewBuffer, firstOutput)

        await project.renderProcessedPreview()
        let secondOutput = try XCTUnwrap(project.processedPreviewBuffer)
        XCTAssertEqual(project.processingState, .ready)
        XCTAssertNotEqual(firstOutput.samples, secondOutput.samples)
    }

    func testWorkflowProgressIncludesCurrentBlockStepAndName() async throws {
        let secondBlockStarted = expectation(description: "Second workflow block started")
        let firstBlock = EffectBlock(type: .clipping, name: "effect.clipping", order: 0)
        let secondBlock = EffectBlock(type: .limiter, name: "effect.limiter", order: 1)
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                WorkflowIdentityProcessor(type: .clipping),
                WorkflowProgressDelayProcessor(type: .limiter, started: secondBlockStarted),
            ])
        )
        let project = AudioProjectViewModel(
            renderer: renderer,
            modulePresetStore: ModulePresetStore(directoryURL: makeTemporaryDirectory()),
            workflowPresetStore: WorkflowPresetStore(directoryURL: makeTemporaryDirectory())
        )
        project.currentWorkflow = Workflow(
            name: "workflow.progress",
            blocks: [firstBlock, secondBlock]
        )
        project.originalAudioBuffer = try SampleAudioFactory.makeDevelopmentSample(duration: 0.05)

        let renderTask = Task {
            await project.renderWorkflowPreview()
        }

        await fulfillment(of: [secondBlockStarted], timeout: 1)
        let didShowSecondBlock = await waitFor {
            project.operationProgress?.step == .block(current: 2, total: 2)
        }
        XCTAssertTrue(didShowSecondBlock)

        let progress = try XCTUnwrap(project.operationProgress)
        XCTAssertEqual(progress.kind, .workflowPreview)
        XCTAssertEqual(progress.itemKey, "effect.limiter")
        XCTAssertEqual(progress.step, .block(current: 2, total: 2))

        await renderTask.value
    }

    private func makeProject() -> AudioProjectViewModel {
        AudioProjectViewModel(
            modulePresetStore: ModulePresetStore(directoryURL: makeTemporaryDirectory()),
            workflowPresetStore: WorkflowPresetStore(directoryURL: makeTemporaryDirectory())
        )
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @MainActor
    private func waitFor(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<50 {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        return condition()
    }
}

private struct WorkflowIdentityProcessor: EffectProcessor {
    let type: EffectType

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        input
    }
}

private final class WorkflowProgressDelayProcessor: EffectProcessor, @unchecked Sendable {
    let type: EffectType
    private let started: XCTestExpectation

    init(type: EffectType, started: XCTestExpectation) {
        self.type = type
        self.started = started
    }

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        started.fulfill()
        Thread.sleep(forTimeInterval: 0.2)
        return input
    }
}
