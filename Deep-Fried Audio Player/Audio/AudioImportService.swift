//
//  AudioImportService.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import AVFoundation
import Foundation

nonisolated protocol AudioImportServicing {
    func importAudio(from url: URL) async throws -> AudioBuffer
}

nonisolated enum AudioImportServiceError: Error, Equatable {
    case unreadableFile
    case emptyAudio
    case unsupportedFormat
    case audioTooLong
    case invalidPCMData
}

nonisolated struct AudioImportService: AudioImportServicing {
    func importAudio(from url: URL) async throws -> AudioBuffer {
        try await Task.detached(priority: .userInitiated) {
            let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            return try AudioFileDecoder.decodeAudioFile(at: url)
        }
        .value
    }
}

nonisolated enum AudioFileDecoder {
    static func decodeAudioFile(at url: URL) throws -> AudioBuffer {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forReading: url,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioImportServiceError.unreadableFile
        }

        guard file.length > 0 else {
            throw AudioImportServiceError.emptyAudio
        }

        guard file.length <= AVAudioFramePosition(AVAudioFrameCount.max) else {
            throw AudioImportServiceError.audioTooLong
        }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw AudioImportServiceError.unsupportedFormat
        }

        do {
            try file.read(into: pcmBuffer)
        } catch {
            throw AudioImportServiceError.unreadableFile
        }

        let frameCount = Int(pcmBuffer.frameLength)
        guard frameCount > 0 else {
            throw AudioImportServiceError.emptyAudio
        }

        guard let channelData = pcmBuffer.floatChannelData else {
            throw AudioImportServiceError.invalidPCMData
        }

        let channelCount = Int(file.processingFormat.channelCount)
        guard channelCount > 0 else {
            throw AudioImportServiceError.unsupportedFormat
        }

        let samples = (0..<channelCount).map { channelIndex in
            Array(
                UnsafeBufferPointer(
                    start: channelData[channelIndex],
                    count: frameCount
                )
            )
        }

        return try AudioBuffer(
            sampleRate: file.processingFormat.sampleRate,
            channelCount: channelCount,
            frames: frameCount,
            samples: samples
        )
    }
}
