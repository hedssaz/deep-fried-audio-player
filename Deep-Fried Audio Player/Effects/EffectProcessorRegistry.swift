//
//  EffectProcessorRegistry.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated struct EffectProcessorRegistry: Sendable {
    static let empty = EffectProcessorRegistry()

    private let processorsByType: [EffectType: any EffectProcessor]

    init(processors: [any EffectProcessor] = []) {
        self.processorsByType = Dictionary(
            processors.map { ($0.type, $0) },
            uniquingKeysWith: { _, new in new }
        )
    }

    func processor(for type: EffectType) -> (any EffectProcessor)? {
        processorsByType[type]
    }
}
