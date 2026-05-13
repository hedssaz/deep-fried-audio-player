//
//  AudioExportService.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/14.
//

import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum AudioExportFormat: String, CaseIterable, Identifiable, Sendable {
    case wav
    case mp3

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .wav:
            "export.wav"
        case .mp3:
            "export.mp3"
        }
    }

    var fileExtension: String {
        switch self {
        case .wav:
            "wav"
        case .mp3:
            "mp3"
        }
    }

    var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .audio
    }

    func defaultFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        return "deep-fried-processed-\(formatter.string(from: date)).\(fileExtension)"
    }
}

nonisolated struct PreparedAudioExport {
    let format: AudioExportFormat
    let document: AudioExportDocument
    let contentType: UTType
    let defaultFileName: String

    init(
        format: AudioExportFormat,
        data: Data,
        date: Date = Date()
    ) {
        self.format = format
        self.document = AudioExportDocument(data: data, contentType: format.contentType)
        self.contentType = format.contentType
        self.defaultFileName = format.defaultFileName(date: date)
    }
}

nonisolated struct AudioExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        AudioExportFormat.allCases.map(\.contentType)
    }

    static var writableContentTypes: [UTType] {
        AudioExportFormat.allCases.map(\.contentType)
    }

    let data: Data
    let contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.data = data
        self.contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated enum AudioExportServiceError: Error, Equatable {
    case emptyAudio
    case invalidFormat
    case formatUnavailable(AudioExportFormat)
    case writeFailed
    case readFailed
}

nonisolated protocol AudioExportServicing: Sendable {
    func isFormatAvailable(_ format: AudioExportFormat) -> Bool
    func export(_ buffer: AudioBuffer, format: AudioExportFormat) async throws -> Data
}

nonisolated struct AudioExportService: AudioExportServicing {
    private let codecCatalog: CodecCapabilityCatalog

    init(codecCatalog: CodecCapabilityCatalog = .current) {
        self.codecCatalog = codecCatalog
    }

    func isFormatAvailable(_ format: AudioExportFormat) -> Bool {
        switch format {
        case .wav:
            true
        case .mp3:
            codecCatalog.capability(for: .mp3)?.supportsRoundTrip == true
        }
    }

    func export(_ buffer: AudioBuffer, format: AudioExportFormat) async throws -> Data {
        let codecCatalog = codecCatalog

        return try await Task.detached(priority: .userInitiated) {
            try Self.exportSynchronously(buffer, format: format, codecCatalog: codecCatalog)
        }
        .value
    }

    private static func exportSynchronously(
        _ buffer: AudioBuffer,
        format: AudioExportFormat,
        codecCatalog: CodecCapabilityCatalog
    ) throws -> Data {
        guard buffer.frames > 0 else {
            throw AudioExportServiceError.emptyAudio
        }

        if format == .mp3,
           codecCatalog.capability(for: .mp3)?.supportsRoundTrip != true {
            throw AudioExportServiceError.formatUnavailable(.mp3)
        }

        let fileURL = temporaryFileURL(format: format)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try? FileManager.default.removeItem(at: fileURL)

        try write(buffer, format: format, codecCatalog: codecCatalog, to: fileURL)

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw AudioExportServiceError.readFailed
        }
    }

    private static func write(
        _ buffer: AudioBuffer,
        format: AudioExportFormat,
        codecCatalog: CodecCapabilityCatalog,
        to fileURL: URL
    ) throws {
        let pcmBuffer: AVAudioPCMBuffer
        do {
            pcmBuffer = try AudioBufferPCMBridge.makePCMBuffer(from: buffer)
        } catch {
            throw AudioExportServiceError.invalidFormat
        }

        let settings: [String: Any]
        switch format {
        case .wav:
            settings = wavSettings(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount)
        case .mp3:
            guard let capability = codecCatalog.capability(for: .mp3),
                  let audioFormatID = capability.audioFormatID else {
                throw AudioExportServiceError.formatUnavailable(.mp3)
            }
            settings = encodedSettings(
                audioFormatID: audioFormatID,
                sampleRate: buffer.sampleRate,
                channelCount: buffer.channelCount,
                bitRateKbps: capability.defaultBitRateKbps
            )
        }

        do {
            let outputFile = try AVAudioFile(
                forWriting: fileURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: pcmBuffer)
            if #available(iOS 18.0, macOS 15.0, *) {
                outputFile.close()
            }
        } catch {
            throw AudioExportServiceError.writeFailed
        }
    }

    private static func wavSettings(sampleRate: Double, channelCount: Int) -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true,
        ]
    }

    private static func encodedSettings(
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

    private static func temporaryFileURL(format: AudioExportFormat) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "deep-fried-export-\(UUID().uuidString)",
                isDirectory: false
            )
            .appendingPathExtension(format.fileExtension)
    }
}
