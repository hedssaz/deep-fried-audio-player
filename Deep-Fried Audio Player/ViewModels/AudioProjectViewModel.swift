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
    @Published var selectedSingleModule = EffectBlock(
        type: .sampleRateReduction,
        name: "effect.sampleRateReduction",
        order: 0
    )
    @Published var currentWorkflow = Workflow(name: "workflow.untitled")
    @Published var processingState: ProcessingState = .empty
    @Published var playbackState: PlaybackState = .stopped
}
