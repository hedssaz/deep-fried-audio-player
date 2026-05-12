//
//  EffectProcessor.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated protocol EffectProcessor: Sendable {
    var type: EffectType { get }

    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer
}
