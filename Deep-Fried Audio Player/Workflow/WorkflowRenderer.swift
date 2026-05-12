//
//  WorkflowRenderer.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated struct WorkflowRenderBlockContext: Equatable, Sendable {
    let id: UUID
    let type: EffectType
    let name: String
    let order: Int

    init(block: EffectBlock) {
        self.id = block.id
        self.type = block.type
        self.name = block.name
        self.order = block.order
    }
}

nonisolated enum WorkflowRendererError: Error, Equatable {
    case missingProcessor(block: WorkflowRenderBlockContext)
    case blockFailed(block: WorkflowRenderBlockContext, underlyingMessage: String)
    case invalidSafetyPeak(Float)
}

actor WorkflowRenderer {
    private let registry: EffectProcessorRegistry
    private let safetyPeak: Float
    private var activeRenderID: UUID?
    private var activeRenderTask: Task<AudioBuffer, Error>?

    init(
        registry: EffectProcessorRegistry = .empty,
        safetyPeak: Float = 0.98
    ) {
        self.registry = registry
        self.safetyPeak = safetyPeak
    }

    func render(_ input: AudioBuffer, workflow: Workflow) async throws -> AudioBuffer {
        activeRenderTask?.cancel()

        let renderID = UUID()
        let registry = registry
        let safetyPeak = safetyPeak
        let task = Task.detached(priority: .userInitiated) {
            try Self.renderSynchronously(
                input,
                workflow: workflow,
                registry: registry,
                safetyPeak: safetyPeak
            )
        }

        activeRenderID = renderID
        activeRenderTask = task

        do {
            let output = try await task.value
            clearActiveRenderIfNeeded(renderID: renderID)
            return output
        } catch {
            clearActiveRenderIfNeeded(renderID: renderID)
            throw error
        }
    }

    private func clearActiveRenderIfNeeded(renderID: UUID) {
        guard activeRenderID == renderID else {
            return
        }

        activeRenderID = nil
        activeRenderTask = nil
    }

    private nonisolated static func renderSynchronously(
        _ input: AudioBuffer,
        workflow: Workflow,
        registry: EffectProcessorRegistry,
        safetyPeak: Float
    ) throws -> AudioBuffer {
        let enabledBlocks = workflow.orderedBlocks.filter(\.isEnabled)

        guard !enabledBlocks.isEmpty else {
            return input
        }

        var output = input

        for block in enabledBlocks {
            try Task.checkCancellation()

            guard let processor = registry.processor(for: block.type) else {
                throw WorkflowRendererError.missingProcessor(
                    block: WorkflowRenderBlockContext(block: block)
                )
            }

            do {
                output = try processor.process(output, block: block)
            } catch let error as CancellationError {
                throw error
            } catch {
                throw WorkflowRendererError.blockFailed(
                    block: WorkflowRenderBlockContext(block: block),
                    underlyingMessage: String(describing: error)
                )
            }
        }

        try Task.checkCancellation()
        return try applySafetyProtection(to: output, safetyPeak: safetyPeak)
    }

    private nonisolated static func applySafetyProtection(
        to buffer: AudioBuffer,
        safetyPeak: Float
    ) throws -> AudioBuffer {
        guard safetyPeak.isFinite, safetyPeak > 0 else {
            throw WorkflowRendererError.invalidSafetyPeak(safetyPeak)
        }

        let peak = buffer.samples.reduce(Float.zero) { currentPeak, channelSamples in
            channelSamples.reduce(currentPeak) { channelPeak, sample in
                max(channelPeak, abs(sample))
            }
        }
        let scale = peak > safetyPeak ? safetyPeak / peak : 1
        let protectedSamples = buffer.samples.map { channelSamples in
            channelSamples.map { $0 * scale }
        }

        return try AudioBuffer(
            sampleRate: buffer.sampleRate,
            channelCount: buffer.channelCount,
            frames: buffer.frames,
            samples: protectedSamples
        )
    }
}
