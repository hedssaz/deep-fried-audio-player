//
//  Workflow.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct Workflow: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var blocks: [EffectBlock]
    var createdAt: Date
    var updatedAt: Date

    var orderedBlocks: [EffectBlock] {
        blocks.enumerated()
            .sorted { left, right in
                if left.element.order == right.element.order {
                    return left.offset < right.offset
                }

                return left.element.order < right.element.order
            }
            .map(\.element)
    }

    init(
        id: UUID = UUID(),
        name: String,
        blocks: [EffectBlock] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
