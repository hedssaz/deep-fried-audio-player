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
}
