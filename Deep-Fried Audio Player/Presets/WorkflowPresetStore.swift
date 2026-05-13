//
//  WorkflowPresetStore.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated enum WorkflowPresetStoreError: Error, Equatable {
    case emptyName
    case presetNotFound(UUID)
}

actor WorkflowPresetStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = fileManager
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WorkflowPresets", isDirectory: true)
        }

        self.fileManager = fileManager
    }

    func loadAll() throws -> [WorkflowPreset] {
        try ensureDirectoryExists()

        let presetURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try presetURLs
            .map { url in
                let data = try Data(contentsOf: url)
                return try decoder.decode(WorkflowPreset.self, from: data)
            }
            .sorted { left, right in
                left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }

    func load(id: UUID) throws -> WorkflowPreset {
        let url = fileURL(for: id)

        guard fileManager.fileExists(atPath: url.path) else {
            throw WorkflowPresetStoreError.presetNotFound(id)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        return try decoder.decode(WorkflowPreset.self, from: data)
    }

    func save(_ preset: WorkflowPreset) throws {
        let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw WorkflowPresetStoreError.emptyName
        }

        try ensureDirectoryExists()

        var normalizedPreset = preset
        normalizedPreset.name = trimmedName
        normalizedPreset.workflow.name = trimmedName

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(normalizedPreset)
        try data.write(to: fileURL(for: normalizedPreset.id), options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).json")
    }
}
