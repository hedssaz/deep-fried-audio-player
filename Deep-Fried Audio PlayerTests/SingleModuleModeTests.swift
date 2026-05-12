//
//  SingleModuleModeTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import XCTest
@testable import Deep_Fried_Audio_Player

@MainActor
final class SingleModuleModeTests: XCTestCase {
    func testSingleModuleRenderProducesProcessedFinitePreview() async throws {
        let project = makeProject()

        project.generateSampleAudio()
        await project.renderSingleModulePreview()

        let original = try XCTUnwrap(project.originalAudioBuffer)
        let processed = try XCTUnwrap(project.processedPreviewBuffer)

        XCTAssertEqual(project.processingState, .ready)
        XCTAssertEqual(project.playbackState, .stopped)
        XCTAssertEqual(processed.frames, original.frames)
        XCTAssertTrue(processed.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertNotEqual(processed.samples, original.samples)
    }

    func testSingleModuleParameterChangeUpdatesConfigurationAndOutput() async throws {
        let project = makeProject()
        project.selectSingleModuleType(.clipping)
        project.generateSampleAudio()
        await project.renderSingleModulePreview()

        let firstOutput = try XCTUnwrap(project.processedPreviewBuffer)

        project.updateSingleModuleParameter(
            key: EffectParameterKey.threshold,
            value: .float(0.12)
        )
        await project.renderSingleModulePreview()

        let updatedParameter = try XCTUnwrap(
            project.selectedSingleModule.parameters.first { $0.key == EffectParameterKey.threshold }
        )
        let secondOutput = try XCTUnwrap(project.processedPreviewBuffer)

        XCTAssertEqual(updatedParameter.value, .float(0.12))
        XCTAssertNotEqual(firstOutput.samples, secondOutput.samples)
        XCTAssertTrue(secondOutput.samples.flatMap { $0 }.allSatisfy(\.isFinite))
    }

    func testModulePresetStoreRoundTripsJSON() async throws {
        let store = ModulePresetStore(directoryURL: makeTemporaryDirectory())
        let block = EffectBlock.defaultBlock(type: .bitDepthReduction, order: 0, presetName: "Crunch")
        let preset = ModulePreset(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            name: "Crunch",
            block: block,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        try await store.save(preset)

        let loaded = try await store.load(id: preset.id)
        let allPresets = try await store.loadAll()

        XCTAssertEqual(loaded, preset)
        XCTAssertEqual(allPresets, [preset])
    }

    func testLoadingPresetRestoresModuleTypeParametersAndPresetName() async throws {
        let project = makeProject()
        project.selectSingleModuleType(.bitDepthReduction)
        project.updateSingleModuleParameter(
            key: EffectParameterKey.bits,
            value: .int(3)
        )
        project.modulePresetName = "Pocket Radio"

        let didSave = await project.saveCurrentModulePreset()
        XCTAssertTrue(didSave)
        let savedPresetID = try XCTUnwrap(project.selectedModulePresetID)

        project.selectSingleModuleType(.limiter)
        project.selectedModulePresetID = savedPresetID

        let didLoad = await project.loadSelectedModulePreset()
        XCTAssertTrue(didLoad)

        let restoredParameter = try XCTUnwrap(
            project.selectedSingleModule.parameters.first { $0.key == EffectParameterKey.bits }
        )

        XCTAssertEqual(project.selectedSingleModule.type, .bitDepthReduction)
        XCTAssertEqual(restoredParameter.value, .int(3))
        XCTAssertEqual(project.selectedSingleModule.presetName, "Pocket Radio")
        XCTAssertEqual(project.modulePresetName, "Pocket Radio")
    }

    func testSendingSingleModuleToWorkflowAppendsNextOrderedBlock() {
        let project = makeProject()
        let existingBlock = EffectBlock.defaultBlock(type: .sampleRateReduction, order: 4)
        project.currentWorkflow = Workflow(name: "workflow.existing", blocks: [existingBlock])
        project.selectSingleModuleType(.clipping)
        let selectedID = project.selectedSingleModule.id

        project.sendSingleModuleToWorkflow()

        XCTAssertEqual(project.mode, .workflow)
        XCTAssertEqual(project.currentWorkflow.blocks.count, 2)

        let sentBlock = project.currentWorkflow.blocks[1]
        XCTAssertEqual(sentBlock.type, .clipping)
        XCTAssertEqual(sentBlock.order, 5)
        XCTAssertNotEqual(sentBlock.id, selectedID)
        XCTAssertEqual(sentBlock.parameters, project.selectedSingleModule.parameters)
    }

    private func makeProject() -> AudioProjectViewModel {
        AudioProjectViewModel(
            modulePresetStore: ModulePresetStore(directoryURL: makeTemporaryDirectory())
        )
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
