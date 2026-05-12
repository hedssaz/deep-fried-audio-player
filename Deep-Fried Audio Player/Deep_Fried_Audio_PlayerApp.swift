//
//  Deep_Fried_Audio_PlayerApp.swift
//  Deep-Fried Audio Player
//
//  Created by hedssaz on 2026/5/13.
//

import SwiftUI

@main
struct Deep_Fried_Audio_PlayerApp: App {
    @StateObject private var project = AudioProjectViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(project)
        }
    }
}
