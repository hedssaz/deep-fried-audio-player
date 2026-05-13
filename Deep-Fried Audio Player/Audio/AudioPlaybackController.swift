//
//  AudioPlaybackController.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import AVFoundation
import Foundation

@MainActor
protocol AudioPlaybackControlling {
    func play(
        _ buffer: AudioBuffer,
        completion: @escaping @MainActor () -> Void
    ) async throws
    func stop()
}

nonisolated enum AudioPlaybackControllerError: Error, Equatable {
    case emptyBuffer
    case invalidFormat
    case invalidPCMData
}

nonisolated enum AudioBufferPCMBridge {
    static func makePCMBuffer(from buffer: AudioBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.frames > 0 else {
            throw AudioPlaybackControllerError.emptyBuffer
        }

        guard buffer.channelCount <= Int(AVAudioChannelCount.max),
              buffer.frames <= Int(AVAudioFrameCount.max) else {
            throw AudioPlaybackControllerError.invalidFormat
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.sampleRate,
            channels: AVAudioChannelCount(buffer.channelCount),
            interleaved: false
        ) else {
            throw AudioPlaybackControllerError.invalidFormat
        }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(buffer.frames)
        ) else {
            throw AudioPlaybackControllerError.invalidPCMData
        }

        pcmBuffer.frameLength = AVAudioFrameCount(buffer.frames)

        guard let channelData = pcmBuffer.floatChannelData else {
            throw AudioPlaybackControllerError.invalidPCMData
        }

        for channelIndex in 0..<buffer.channelCount {
            for frameIndex in 0..<buffer.frames {
                channelData[channelIndex][frameIndex] = buffer.samples[channelIndex][frameIndex]
            }
        }

        return pcmBuffer
    }
}

@MainActor
final class AudioPlaybackController: AudioPlaybackControlling {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var activePlaybackID: UUID?

    init() {
        engine.attach(playerNode)
    }

    func play(
        _ buffer: AudioBuffer,
        completion: @escaping @MainActor () -> Void
    ) async throws {
        stop()

        let pcmBuffer = try AudioBufferPCMBridge.makePCMBuffer(from: buffer)
        let playbackID = UUID()

        do {
            #if os(iOS)
            try configureAudioSessionForPlayback()
            #endif

            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: pcmBuffer.format)
            engine.prepare()
            try engine.start()

            activePlaybackID = playbackID
            playerNode.scheduleBuffer(
                pcmBuffer,
                at: nil,
                options: [],
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.activePlaybackID == playbackID else {
                        return
                    }

                    self.stop()
                    completion()
                }
            }
            playerNode.play()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        activePlaybackID = nil
        playerNode.stop()

        if engine.isRunning {
            engine.stop()
        }

        engine.reset()

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
        #endif
    }

    #if os(iOS)
    private func configureAudioSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }
    #endif
}
