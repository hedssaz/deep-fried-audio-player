//
//  EffectBlock.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated struct EffectBlock: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var type: EffectType
    var name: String
    var isEnabled: Bool
    var order: Int
    var parameters: [EffectParameter]
    var presetName: String?

    init(
        id: UUID = UUID(),
        type: EffectType,
        name: String,
        isEnabled: Bool = true,
        order: Int,
        parameters: [EffectParameter] = [],
        presetName: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.isEnabled = isEnabled
        self.order = order
        self.parameters = parameters
        self.presetName = presetName
    }
}
