//
//  FirstEffectProcessorTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import XCTest
@testable import Deep_Fried_Audio_Player

final class FirstEffectProcessorTests: XCTestCase {
    func testBuiltInRegistryContainsFirstRealEffects() {
        for type in EffectType.firstRealEffectTypes {
            XCTAssertNotNil(
                EffectProcessorRegistry.builtIn.processor(for: type),
                "Missing built-in processor for \(type.rawValue)."
            )
        }
    }

    func testDefaultFirstRealEffectBlocksExposeEditableParameters() {
        for type in EffectType.firstRealEffectTypes {
            let block = EffectBlock.defaultBlock(type: type, order: 0)

            XCTAssertEqual(block.type, type)
            XCTAssertEqual(block.name, type.displayNameKey)
            XCTAssertFalse(block.parameters.isEmpty)

            for parameter in block.parameters {
                XCTAssertFalse(parameter.key.isEmpty)
                XCTAssertFalse(parameter.labelKey.isEmpty)
                XCTAssertNotNil(parameter.unitKey)
                XCTAssertTrue(
                    parameter.valueRange != nil || !parameter.choices.isEmpty,
                    "\(parameter.key) should define either a numeric range or choices."
                )
            }
        }
    }

    func testFirstRealEffectsPreserveShapeAndReturnFiniteSamples() throws {
        let input = try makeBuffer()

        for type in EffectType.firstRealEffectTypes {
            let processor = try XCTUnwrap(EffectProcessorRegistry.builtIn.processor(for: type))
            let block = EffectBlock.defaultBlock(type: type, order: 0)

            let output = try processor.process(input, block: block)

            XCTAssertEqual(output.sampleRate, input.sampleRate)
            XCTAssertEqual(output.channelCount, input.channelCount)
            XCTAssertEqual(output.frames, input.frames)
            XCTAssertEqual(output.samples.count, input.samples.count)
            XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
            XCTAssertNotEqual(output.samples, input.samples)
        }
    }

    func testFirstRealEffectOutputsChangeWhenParametersChange() throws {
        let input = try makeBuffer()

        try assertOutputChanges(
            for: .sampleRateReduction,
            first: .choice("22050"),
            second: .choice("8000"),
            parameterKey: EffectParameterKey.targetSampleRate,
            input: input
        )
        try assertOutputChanges(
            for: .bitDepthReduction,
            first: .int(8),
            second: .int(2),
            parameterKey: EffectParameterKey.bits,
            input: input
        )
        try assertOutputChanges(
            for: .clipping,
            first: .float(0.9),
            second: .float(0.2),
            parameterKey: EffectParameterKey.threshold,
            input: input
        )
        try assertOutputChanges(
            for: .limiter,
            first: .float(1.0),
            second: .float(4.0),
            parameterKey: EffectParameterKey.inputGain,
            input: input
        )
    }

    func testDefaultWorkflowRendererCanRenderFirstRealEffect() async throws {
        let input = try makeBuffer()
        let workflow = Workflow(
            name: "workflow.step6",
            blocks: [
                EffectBlock.defaultBlock(type: .clipping, order: 0),
            ]
        )

        let output = try await WorkflowRenderer().render(input, workflow: workflow)

        XCTAssertEqual(output.frames, input.frames)
        XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertNotEqual(output.samples, input.samples)
    }

    private func assertOutputChanges(
        for type: EffectType,
        first: EffectParameterValue,
        second: EffectParameterValue,
        parameterKey: String,
        input: AudioBuffer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let processor = try XCTUnwrap(
            EffectProcessorRegistry.builtIn.processor(for: type),
            file: file,
            line: line
        )

        let firstOutput = try processor.process(
            input,
            block: block(type, setting: parameterKey, to: first)
        )
        let secondOutput = try processor.process(
            input,
            block: block(type, setting: parameterKey, to: second)
        )

        XCTAssertNotEqual(firstOutput.samples, secondOutput.samples, file: file, line: line)
        XCTAssertTrue(firstOutput.samples.flatMap { $0 }.allSatisfy(\.isFinite), file: file, line: line)
        XCTAssertTrue(secondOutput.samples.flatMap { $0 }.allSatisfy(\.isFinite), file: file, line: line)
    }

    private func block(
        _ type: EffectType,
        setting parameterKey: String,
        to value: EffectParameterValue
    ) -> EffectBlock {
        var block = EffectBlock.defaultBlock(type: type, order: 0)
        let parameterIndex = block.parameters.firstIndex { $0.key == parameterKey }

        guard let parameterIndex else {
            return block
        }

        block.parameters[parameterIndex].value = value
        return block
    }

    private func makeBuffer() throws -> AudioBuffer {
        try AudioBuffer(
            sampleRate: 44_100,
            channelCount: 2,
            samples: [
                [-0.9, -0.62, -0.38, -0.11, 0.07, 0.31, 0.68, 0.95],
                [0.83, 0.54, 0.22, -0.04, -0.28, -0.47, -0.71, -0.99],
            ]
        )
    }
}
