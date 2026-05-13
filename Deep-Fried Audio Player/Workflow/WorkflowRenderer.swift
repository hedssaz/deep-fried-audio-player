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

nonisolated struct WorkflowRenderProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case preparing
        case processingBlock
        case codecPreparing
        case codecEncoding
        case codecDecoding
        case codecFinalizing
        case finalizing
        case completed
    }

    let progress: Double
    let phase: Phase
    let currentBlock: WorkflowRenderBlockContext?
    let currentBlockIndex: Int?
    let totalBlockCount: Int
}

nonisolated struct EffectProcessorProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case codecPreparing
        case codecEncoding
        case codecDecoding
        case codecFinalizing
    }

    let phase: Phase
}

nonisolated protocol ProgressReportingEffectProcessor: EffectProcessor {
    func process(
        _ input: AudioBuffer,
        block: EffectBlock,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> AudioBuffer
}

actor WorkflowRenderer {
    private let registry: EffectProcessorRegistry
    private let safetyPeak: Float
    private var activeRenderID: UUID?
    private var activeRenderTask: Task<AudioBuffer, Error>?

    init(
        registry: EffectProcessorRegistry = .builtIn,
        safetyPeak: Float = 0.98
    ) {
        self.registry = registry
        self.safetyPeak = safetyPeak
    }

    func render(
        _ input: AudioBuffer,
        workflow: Workflow,
        progress: @escaping @Sendable (WorkflowRenderProgress) -> Void = { _ in }
    ) async throws -> AudioBuffer {
        activeRenderTask?.cancel()

        let renderID = UUID()
        let registry = registry
        let safetyPeak = safetyPeak
        let task = Task.detached(priority: .userInitiated) {
            try Self.renderSynchronously(
                input,
                workflow: workflow,
                registry: registry,
                safetyPeak: safetyPeak,
                progress: progress
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

    func cancelActiveRender() {
        activeRenderID = nil
        activeRenderTask?.cancel()
        activeRenderTask = nil
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
        safetyPeak: Float,
        progress: @escaping @Sendable (WorkflowRenderProgress) -> Void
    ) throws -> AudioBuffer {
        let enabledBlocks = workflow.orderedBlocks.filter(\.isEnabled)

        guard !enabledBlocks.isEmpty else {
            progress(
                WorkflowRenderProgress(
                    progress: 1,
                    phase: .completed,
                    currentBlock: nil,
                    currentBlockIndex: nil,
                    totalBlockCount: 0
                )
            )
            return input
        }

        var output = input
        let totalBlockCount = enabledBlocks.count

        progress(
            WorkflowRenderProgress(
                progress: 0,
                phase: .preparing,
                currentBlock: nil,
                currentBlockIndex: nil,
                totalBlockCount: totalBlockCount
            )
        )

        for (blockIndex, block) in enabledBlocks.enumerated() {
            try Task.checkCancellation()
            let blockContext = WorkflowRenderBlockContext(block: block)
            let blockBaseProgress = Double(blockIndex) / Double(totalBlockCount)
            let blockWeight = 1 / Double(totalBlockCount)

            progress(
                WorkflowRenderProgress(
                    progress: blockBaseProgress,
                    phase: .processingBlock,
                    currentBlock: blockContext,
                    currentBlockIndex: blockIndex,
                    totalBlockCount: totalBlockCount
                )
            )

            guard let processor = registry.processor(for: block.type) else {
                throw WorkflowRendererError.missingProcessor(
                    block: blockContext
                )
            }

            do {
                if let progressReportingProcessor = processor as? any ProgressReportingEffectProcessor {
                    output = try progressReportingProcessor.process(output, block: block) { processorProgress in
                        progress(
                            WorkflowRenderProgress(
                                progress: blockBaseProgress + processorProgress.progressFraction * blockWeight,
                                phase: processorProgress.workflowPhase,
                                currentBlock: blockContext,
                                currentBlockIndex: blockIndex,
                                totalBlockCount: totalBlockCount
                            )
                        )
                    }
                } else {
                    output = try processor.process(output, block: block)
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                throw WorkflowRendererError.blockFailed(
                    block: blockContext,
                    underlyingMessage: String(describing: error)
                )
            }

            progress(
                WorkflowRenderProgress(
                    progress: Double(blockIndex + 1) / Double(totalBlockCount),
                    phase: .processingBlock,
                    currentBlock: blockContext,
                    currentBlockIndex: blockIndex,
                    totalBlockCount: totalBlockCount
                )
            )
        }

        try Task.checkCancellation()
        progress(
            WorkflowRenderProgress(
                progress: 1,
                phase: .finalizing,
                currentBlock: nil,
                currentBlockIndex: nil,
                totalBlockCount: totalBlockCount
            )
        )

        let protectedOutput = try applySafetyProtection(to: output, safetyPeak: safetyPeak)
        progress(
            WorkflowRenderProgress(
                progress: 1,
                phase: .completed,
                currentBlock: nil,
                currentBlockIndex: nil,
                totalBlockCount: totalBlockCount
            )
        )
        return protectedOutput
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

private extension EffectProcessorProgress {
    nonisolated var workflowPhase: WorkflowRenderProgress.Phase {
        switch phase {
        case .codecPreparing:
            .codecPreparing
        case .codecEncoding:
            .codecEncoding
        case .codecDecoding:
            .codecDecoding
        case .codecFinalizing:
            .codecFinalizing
        }
    }

    nonisolated var progressFraction: Double {
        switch phase {
        case .codecPreparing:
            0.05
        case .codecEncoding:
            0.25
        case .codecDecoding:
            0.65
        case .codecFinalizing:
            0.9
        }
    }
}
