//
//  CodecRoundTripProcessor.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import AVFoundation
import Foundation

nonisolated enum CodecRoundTripProcessorError: Error, Equatable, CustomStringConvertible {
    case unsupportedEffectType(EffectType)
    case noAvailableCodec
    case unknownCodec(String)
    case codecUnavailable(CodecID, CodecAvailabilityStatus)
    case missingCodecFormat(CodecID)
    case emptyDecodedOutput(CodecID)

    var description: String {
        switch self {
        case let .unsupportedEffectType(type):
            "Codec round-trip processor cannot handle effect type '\(type.rawValue)'."
        case .noAvailableCodec:
            "No real encode/decode codec is available on this device."
        case let .unknownCodec(value):
            "Unknown codec '\(value)'."
        case let .codecUnavailable(id, status):
            "Codec '\(id.rawValue)' is \(status.rawValue) and cannot be used for a real round-trip."
        case let .missingCodecFormat(id):
            "Codec '\(id.rawValue)' does not define an encodable AVFoundation format."
        case let .emptyDecodedOutput(id):
            "Codec '\(id.rawValue)' produced empty decoded output."
        }
    }
}

nonisolated struct CodecRoundTripProcessor: ProgressReportingEffectProcessor {
    let type: EffectType

    private let catalog: CodecCapabilityCatalog

    init(
        type: EffectType,
        catalog: CodecCapabilityCatalog = .current
    ) {
        precondition(
            type == .bitrateReduction || type == .lowQualityCodec,
            "CodecRoundTripProcessor only supports codec effect types."
        )

        self.type = type
        self.catalog = catalog
    }

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer {
        try process(input, block: block) { _ in }
    }

    func process(
        _ input: AudioBuffer,
        block: EffectBlock,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void
    ) throws -> AudioBuffer {
        progress(EffectProcessorProgress(phase: .codecPreparing, fractionCompleted: 0.05))

        let selectedCodecID = try selectedCodecID(from: block)
        guard let capability = catalog.capability(for: selectedCodecID) else {
            throw CodecRoundTripProcessorError.unknownCodec(selectedCodecID.rawValue)
        }

        guard capability.supportsRoundTrip else {
            throw CodecRoundTripProcessorError.codecUnavailable(
                selectedCodecID,
                capability.status
            )
        }

        let bitRateKbps = try resolvedBitRateKbps(
            from: block,
            capability: capability,
            channelCount: input.channelCount
        )

        return try CodecRoundTripFile.render(
            input,
            capability: capability,
            bitRateKbps: bitRateKbps,
            progress: progress
        )
    }

    private func selectedCodecID(from block: EffectBlock) throws -> CodecID {
        guard let defaultCodec = catalog.defaultRoundTripCapability?.id else {
            throw CodecRoundTripProcessorError.noAvailableCodec
        }

        let rawValue = try block.choiceParameter(
            EffectParameterKey.codec,
            default: defaultCodec.rawValue
        )

        guard let codecID = CodecID(rawValue: rawValue) else {
            throw CodecRoundTripProcessorError.unknownCodec(rawValue)
        }

        return codecID
    }

    private func resolvedBitRateKbps(
        from block: EffectBlock,
        capability: CodecCapability,
        channelCount: Int
    ) throws -> Int? {
        guard let bitRateRange = capability.bitRateRange else {
            return nil
        }

        let defaultBitRateKbps = capability.defaultBitRateKbps ?? bitRateRange.minKbps
        let requestedBitRateKbps = try block.intParameter(
            EffectParameterKey.bitRateKbps,
            default: defaultBitRateKbps
        )
        let safeMinimumBitRateKbps = max(
            bitRateRange.minKbps,
            min(bitRateRange.maxKbps, max(1, channelCount) * 32)
        )

        return max(requestedBitRateKbps, safeMinimumBitRateKbps)
            .clamped(to: bitRateRange.closedRange)
    }
}

nonisolated enum CodecRoundTripFile {
    static func canRoundTrip(capability: CodecCapability) -> Bool {
        do {
            let probeBuffer = try AudioBuffer(
                sampleRate: 44_100,
                channelCount: 1,
                samples: [Array(repeating: Float.zero, count: 128)]
            )
            let output = try render(
                probeBuffer,
                capability: capability,
                bitRateKbps: capability.defaultBitRateKbps
            )

            return output.frames > 0
        } catch {
            return false
        }
    }

    static func render(
        _ input: AudioBuffer,
        capability: CodecCapability,
        bitRateKbps: Int?,
        progress: @escaping @Sendable (EffectProcessorProgress) -> Void = { _ in }
    ) throws -> AudioBuffer {
        guard let audioFormatID = capability.audioFormatID,
              let fileExtension = capability.fileExtension else {
            throw CodecRoundTripProcessorError.missingCodecFormat(capability.id)
        }

        let pcmBuffer = try AudioBufferPCMBridge.makePCMBuffer(from: input)
        let fileURL = temporaryFileURL(
            codecID: capability.id,
            fileExtension: fileExtension
        )
        let settings = encodingSettings(
            audioFormatID: audioFormatID,
            sampleRate: input.sampleRate,
            channelCount: input.channelCount,
            bitRateKbps: bitRateKbps
        )

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        try? FileManager.default.removeItem(at: fileURL)

        do {
            progress(EffectProcessorProgress(phase: .codecEncoding, fractionCompleted: 0.25))
            let outputFile = try AVAudioFile(
                forWriting: fileURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: pcmBuffer)
            outputFile.close()
        }

        progress(EffectProcessorProgress(phase: .codecDecoding, fractionCompleted: 0.65))
        let decoded = try AudioFileDecoder.decodeAudioFile(at: fileURL)
        guard decoded.frames > 0 else {
            throw CodecRoundTripProcessorError.emptyDecodedOutput(capability.id)
        }

        progress(EffectProcessorProgress(phase: .codecFinalizing, fractionCompleted: 0.9))
        return decoded
    }

    private static func temporaryFileURL(
        codecID: CodecID,
        fileExtension: String
    ) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "deep-fried-codec-\(codecID.rawValue)-\(UUID().uuidString)",
                isDirectory: false
            )
            .appendingPathExtension(fileExtension)
    }

    private static func encodingSettings(
        audioFormatID: AudioFormatID,
        sampleRate: Double,
        channelCount: Int,
        bitRateKbps: Int?
    ) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: Int(audioFormatID),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        if let bitRateKbps {
            settings[AVEncoderBitRateKey] = bitRateKbps * 1_000
        }

        return settings
    }
}
