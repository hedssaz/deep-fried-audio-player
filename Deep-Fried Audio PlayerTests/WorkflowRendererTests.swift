//
//  WorkflowRendererTests.swift
//  Deep-Fried Audio PlayerTests
//
//  Created by Codex on 2026/5/13.
//

import XCTest
@testable import Deep_Fried_Audio_Player

final class WorkflowRendererTests: XCTestCase {
    func testZeroEnabledBlocksReturnsOriginalAudio() async throws {
        let input = try makeBuffer(samples: [[0.1, -0.2, 0.3]])
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                GainProcessor(type: .clipping, multiplier: 0.5),
            ])
        )

        let output = try await renderer.render(input, workflow: Workflow(name: "workflow.empty"))

        XCTAssertEqual(output, input)
    }

    func testDisabledBlocksAreBypassedWithoutProcessorLookup() async throws {
        let input = try makeBuffer(samples: [[0.1, -0.2, 0.3]])
        let disabledBlock = EffectBlock(
            type: .spectralDamage,
            name: "effect.spectralDamage",
            isEnabled: false,
            order: 0
        )
        let workflow = Workflow(name: "workflow.disabled", blocks: [disabledBlock])
        let renderer = WorkflowRenderer(registry: .empty)

        let output = try await renderer.render(input, workflow: workflow)

        XCTAssertEqual(output, input)
    }

    func testOneEnabledProcessorReturnsChangedAudio() async throws {
        let input = try makeBuffer(samples: [[0.2, -0.4, 0.6]])
        let block = EffectBlock(type: .clipping, name: "effect.clipping", order: 0)
        let workflow = Workflow(name: "workflow.changed", blocks: [block])
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                GainProcessor(type: .clipping, multiplier: 0.5),
            ])
        )

        let output = try await renderer.render(input, workflow: workflow)

        XCTAssertNotEqual(output, input)
        XCTAssertEqual(output.samples, [[0.1, -0.2, 0.3]])
    }

    func testProcessorsRunInWorkflowOrder() async throws {
        let input = try makeBuffer(samples: [[0.1]])
        let multiplyBlock = EffectBlock(type: .limiter, name: "effect.limiter", order: 1)
        let addBlock = EffectBlock(type: .clipping, name: "effect.clipping", order: 0)
        let workflow = Workflow(name: "workflow.order", blocks: [multiplyBlock, addBlock])
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                AddProcessor(type: .clipping, offset: 0.1),
                GainProcessor(type: .limiter, multiplier: 2),
            ])
        )

        let output = try await renderer.render(input, workflow: workflow)

        XCTAssertEqual(output.samples[0][0], 0.4, accuracy: 0.000_001)
    }

    func testOutputSafetyProtectionLimitsPeakAndKeepsSamplesFinite() async throws {
        let input = try makeBuffer(samples: [[0.25, -0.25]])
        let block = EffectBlock(type: .clipping, name: "effect.clipping", order: 0)
        let workflow = Workflow(name: "workflow.safety", blocks: [block])
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                FixedOutputProcessor(
                    type: .clipping,
                    outputSamples: [[2.0, -4.0]]
                ),
            ])
        )

        let output = try await renderer.render(input, workflow: workflow)
        let peak = output.samples.flatMap { $0 }.map(abs).max() ?? 0

        XCTAssertLessThanOrEqual(peak, 0.98)
        XCTAssertTrue(output.samples.flatMap { $0 }.allSatisfy(\.isFinite))
        XCTAssertEqual(output.frames, input.frames)
        XCTAssertEqual(output.channelCount, input.channelCount)
    }

    func testMissingProcessorErrorIdentifiesBlock() async throws {
        let input = try makeBuffer(samples: [[0.1]])
        let blockID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let block = EffectBlock(
            id: blockID,
            type: .spectralDamage,
            name: "effect.spectralDamage",
            order: 0
        )
        let workflow = Workflow(name: "workflow.missing", blocks: [block])
        let renderer = WorkflowRenderer(registry: .empty)

        do {
            _ = try await renderer.render(input, workflow: workflow)
            XCTFail("Expected missing processor error.")
        } catch WorkflowRendererError.missingProcessor(let context) {
            XCTAssertEqual(context.id, blockID)
            XCTAssertEqual(context.type, .spectralDamage)
            XCTAssertEqual(context.name, "effect.spectralDamage")
            XCTAssertEqual(context.order, 0)
        }
    }

    func testFailingProcessorErrorIdentifiesBlock() async throws {
        let input = try makeBuffer(samples: [[0.1]])
        let blockID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let block = EffectBlock(
            id: blockID,
            type: .clipping,
            name: "effect.clipping",
            order: 0
        )
        let workflow = Workflow(name: "workflow.failure", blocks: [block])
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                ThrowingProcessor(type: .clipping),
            ])
        )

        do {
            _ = try await renderer.render(input, workflow: workflow)
            XCTFail("Expected processor failure error.")
        } catch WorkflowRendererError.blockFailed(let context, let underlyingMessage) {
            XCTAssertEqual(context.id, blockID)
            XCTAssertEqual(context.type, .clipping)
            XCTAssertEqual(context.name, "effect.clipping")
            XCTAssertTrue(underlyingMessage.contains("boom"))
        }
    }

    func testStartingNewRenderCancelsStaleRender() async throws {
        let input = try makeBuffer(samples: [[0.1]])
        let started = expectation(description: "First render started")
        let cancelled = expectation(description: "First render cancelled")
        let block = EffectBlock(type: .clipping, name: "effect.clipping", order: 0)
        let slowWorkflow = Workflow(name: "workflow.slow", blocks: [block])
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                CancellableDelayProcessor(
                    type: .clipping,
                    started: started,
                    cancelled: cancelled
                ),
            ])
        )

        let staleRender = Task {
            try await renderer.render(input, workflow: slowWorkflow)
        }

        await fulfillment(of: [started], timeout: 1)

        let freshOutput = try await renderer.render(
            input,
            workflow: Workflow(name: "workflow.fresh")
        )

        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(freshOutput, input)

        do {
            _ = try await staleRender.value
            XCTFail("Expected stale render to be cancelled.")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testMultiBlockProgressIsMonotonicAndCompletes() async throws {
        let input = try makeBuffer(samples: [[0.1, -0.2, 0.3]])
        let workflow = Workflow(
            name: "workflow.progress",
            blocks: [
                EffectBlock(type: .clipping, name: "effect.clipping", order: 0),
                EffectBlock(type: .limiter, name: "effect.limiter", order: 1),
            ]
        )
        let progressLog = WorkflowProgressLog()
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                GainProcessor(type: .clipping, multiplier: 0.5),
                GainProcessor(type: .limiter, multiplier: 0.5),
            ])
        )

        _ = try await renderer.render(input, workflow: workflow) { progress in
            progressLog.append(progress.progress)
        }

        let values = progressLog.values()
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values.last ?? -1, 1.0, accuracy: 0.000_001)

        for (previous, current) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(previous, current + 0.000_001)
        }
    }

    func testSingleBlockProcessorProgressEmitsIntermediateWorkflowProgress() async throws {
        let input = try makeBuffer(samples: [[0.1, -0.2, 0.3]])
        let workflow = Workflow(
            name: "workflow.processorProgress",
            blocks: [
                EffectBlock(type: .clipping, name: "effect.clipping", order: 0),
            ]
        )
        let progressLog = WorkflowProgressLog()
        let renderer = WorkflowRenderer(
            registry: EffectProcessorRegistry(processors: [
                FractionalProgressProcessor(type: .clipping, fractions: [0.25, 0.5, 0.75]),
            ])
        )

        _ = try await renderer.render(input, workflow: workflow) { progress in
            progressLog.append(progress.progress)
        }

        let values = progressLog.values()
        XCTAssertTrue(values.contains { $0 > 0 && $0 < 1 })
        XCTAssertTrue(values.contains { abs($0 - 0.5) < 0.000_001 })
        XCTAssertEqual(values.last ?? -1, 1.0, accuracy: 0.000_001)
    }

    private func makeBuffer(samples: [[Float]]) throws -> AudioBuffer {
        try AudioBuffer(
            sampleRate: 44_100,
            channelCount: samples.count,
            samples: samples
        )
    }
}

private final class WorkflowProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var progressValues: [Double] = []

    func append(_ value: Double) {
        lock.withLock {
            progressValues.append(value)
        }
    }

    func values() -> [Double] {
        lock.withLock {
            progressValues
        }
    }
}

private struct GainProcessor: EffectProcessor {
    let type: EffectType
    let multiplier: Float

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: input.samples.map { channelSamples in
                channelSamples.map { $0 * multiplier }
            }
        )
    }
}

private struct AddProcessor: EffectProcessor {
    let type: EffectType
    let offset: Float

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: input.samples.map { channelSamples in
                channelSamples.map { $0 + offset }
            }
        )
    }
}

private struct FixedOutputProcessor: EffectProcessor {
    let type: EffectType
    let outputSamples: [[Float]]

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        try AudioBuffer(
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            frames: input.frames,
            samples: outputSamples
        )
    }
}

private struct ThrowingProcessor: EffectProcessor {
    enum TestError: Error {
        case boom
    }

    let type: EffectType

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        throw TestError.boom
    }
}

private final class CancellableDelayProcessor: EffectProcessor, @unchecked Sendable {
    let type: EffectType
    private let started: XCTestExpectation
    private let cancelled: XCTestExpectation

    init(
        type: EffectType,
        started: XCTestExpectation,
        cancelled: XCTestExpectation
    ) {
        self.type = type
        self.started = started
        self.cancelled = cancelled
    }

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        started.fulfill()

        for _ in 0..<100 {
            if Task.isCancelled {
                cancelled.fulfill()
                throw CancellationError()
            }

            Thread.sleep(forTimeInterval: 0.01)
        }

        return input
    }
}

private struct FractionalProgressProcessor: ProgressReportingEffectProcessor {
    let type: EffectType
    let fractions: [Double]

    func process(
        _ input: AudioBuffer,
        block: EffectBlock,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> AudioBuffer {
        for fraction in fractions {
            progress(EffectProcessorProgress(fractionCompleted: fraction))
        }

        return input
    }
}
