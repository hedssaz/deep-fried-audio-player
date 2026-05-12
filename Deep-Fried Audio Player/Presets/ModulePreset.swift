//
//  ModulePreset.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated struct ModulePreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var block: EffectBlock
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        block: EffectBlock,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.block = block
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
