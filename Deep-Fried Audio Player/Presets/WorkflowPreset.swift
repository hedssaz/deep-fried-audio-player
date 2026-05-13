//
//  WorkflowPreset.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import Foundation

nonisolated struct WorkflowPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var workflow: Workflow
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        workflow: Workflow,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.workflow = workflow
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
