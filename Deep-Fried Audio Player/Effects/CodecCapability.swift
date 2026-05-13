//
//  CodecCapability.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import AVFoundation
import Foundation

nonisolated enum CodecID: String, CaseIterable, Codable, Identifiable, Sendable {
    case aac
    case mp3
    case appleLossless = "apple-lossless"
    case amrNB = "amr-nb"
    case speex
    case g711
    case g729

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .aac:
            "codec.aac"
        case .mp3:
            "codec.mp3"
        case .appleLossless:
            "codec.appleLossless"
        case .amrNB:
            "codec.amrNB"
        case .speex:
            "codec.speex"
        case .g711:
            "codec.g711"
        case .g729:
            "codec.g729"
        }
    }
}

nonisolated enum CodecAvailabilityStatus: String, Codable, Sendable {
    case available
    case unavailable
    case planned

    var labelKey: String {
        switch self {
        case .available:
            "codec.status.available"
        case .unavailable:
            "codec.status.unavailable"
        case .planned:
            "codec.status.planned"
        }
    }
}

nonisolated struct CodecBitRateRange: Codable, Equatable, Sendable {
    let minKbps: Int
    let maxKbps: Int

    var closedRange: ClosedRange<Int> {
        minKbps...maxKbps
    }
}

nonisolated struct CodecCapability: Codable, Equatable, Identifiable, Sendable {
    let id: CodecID
    let status: CodecAvailabilityStatus
    let audioFormatID: AudioFormatID?
    let fileExtension: String?
    let defaultBitRateKbps: Int?
    let bitRateRange: CodecBitRateRange?
    let unavailableReasonKey: String?

    var labelKey: String {
        id.labelKey
    }

    var statusLabelKey: String {
        status.labelKey
    }

    var supportsRoundTrip: Bool {
        status == .available && audioFormatID != nil && fileExtension != nil
    }
}

nonisolated struct CodecCapabilityCatalog: Codable, Equatable, Sendable {
    static let current = detectCurrent()

    let capabilities: [CodecCapability]

    var availableRoundTripCapabilities: [CodecCapability] {
        let capabilitiesByID = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.id, $0) })

        return Self.preferredRoundTripCodecOrder.compactMap { id in
            guard let capability = capabilitiesByID[id],
                  capability.supportsRoundTrip else {
                return nil
            }

            return capability
        }
    }

    var hasAvailableRoundTripCodec: Bool {
        !availableRoundTripCapabilities.isEmpty
    }

    var defaultRoundTripCapability: CodecCapability? {
        availableRoundTripCapabilities.first
    }

    func capability(for id: CodecID) -> CodecCapability? {
        capabilities.first { $0.id == id }
    }

    func availableRoundTripChoices() -> [EffectParameterChoice] {
        availableRoundTripCapabilities.map { capability in
            EffectParameterChoice(
                value: capability.id.rawValue,
                labelKey: capability.labelKey
            )
        }
    }

    private static let preferredRoundTripCodecOrder: [CodecID] = [
        .aac,
        .mp3,
        .appleLossless,
    ]

    private static func detectCurrent() -> CodecCapabilityCatalog {
        CodecCapabilityCatalog(
            capabilities: CodecID.allCases.map(makeCapability)
        )
    }

    private static func makeCapability(for id: CodecID) -> CodecCapability {
        switch id {
        case .aac:
            return probedSystemCapability(
                id: id,
                audioFormatID: kAudioFormatMPEG4AAC,
                fileExtension: "m4a",
                defaultBitRateKbps: 64,
                bitRateRange: CodecBitRateRange(minKbps: 16, maxKbps: 320)
            )
        case .mp3:
            return probedSystemCapability(
                id: id,
                audioFormatID: kAudioFormatMPEGLayer3,
                fileExtension: "mp3",
                defaultBitRateKbps: 64,
                bitRateRange: CodecBitRateRange(minKbps: 32, maxKbps: 320)
            )
        case .appleLossless:
            return probedSystemCapability(
                id: id,
                audioFormatID: kAudioFormatAppleLossless,
                fileExtension: "m4a",
                defaultBitRateKbps: nil,
                bitRateRange: nil
            )
        case .amrNB:
            return unavailableCapability(
                id: id,
                status: .unavailable,
                reasonKey: "codec.reason.noRoundTripSupport"
            )
        case .speex:
            return unavailableCapability(
                id: id,
                status: .planned,
                reasonKey: "codec.reason.planned"
            )
        case .g711:
            return unavailableCapability(
                id: id,
                status: .unavailable,
                reasonKey: "codec.reason.noRoundTripSupport"
            )
        case .g729:
            return unavailableCapability(
                id: id,
                status: .planned,
                reasonKey: "codec.reason.planned"
            )
        }
    }

    private static func probedSystemCapability(
        id: CodecID,
        audioFormatID: AudioFormatID,
        fileExtension: String,
        defaultBitRateKbps: Int?,
        bitRateRange: CodecBitRateRange?
    ) -> CodecCapability {
        let candidate = CodecCapability(
            id: id,
            status: .available,
            audioFormatID: audioFormatID,
            fileExtension: fileExtension,
            defaultBitRateKbps: defaultBitRateKbps,
            bitRateRange: bitRateRange,
            unavailableReasonKey: nil
        )

        guard CodecRoundTripFile.canRoundTrip(capability: candidate) else {
            return CodecCapability(
                id: id,
                status: .unavailable,
                audioFormatID: audioFormatID,
                fileExtension: fileExtension,
                defaultBitRateKbps: defaultBitRateKbps,
                bitRateRange: bitRateRange,
                unavailableReasonKey: "codec.reason.unavailableOnDevice"
            )
        }

        return candidate
    }

    private static func unavailableCapability(
        id: CodecID,
        status: CodecAvailabilityStatus,
        reasonKey: String
    ) -> CodecCapability {
        CodecCapability(
            id: id,
            status: status,
            audioFormatID: nil,
            fileExtension: nil,
            defaultBitRateKbps: nil,
            bitRateRange: nil,
            unavailableReasonKey: reasonKey
        )
    }
}
