//
//  ContentView.swift
//  Deep-Fried Audio Player
//
//  Created by hedssaz on 2026/5/13.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var project: AudioProjectViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
    }

    private var compactLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modeSection
                    audioSourceSection
                    playbackSection
                    processingSection
                    waveformSection
                    editorSection
                }
                .padding()
            }
            .navigationTitle(Text("home.title"))
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                Section {
                    modePicker
                } header: {
                    Text("mode.title")
                }

                Section {
                    audioSourceControls
                } header: {
                    Text("section.audioSource")
                }

                Section {
                    playbackControls
                } header: {
                    Text("section.playback")
                }
            }
            .navigationTitle(Text("home.title"))
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    processingSection
                    waveformSection
                    editorSection
                }
                .padding()
            }
            .navigationTitle(Text(LocalizedStringKey(project.mode.localizationKey)))
        }
    }

    private var modeSection: some View {
        ShellSection(titleKey: "mode.title", systemImage: "switch.2") {
            modePicker
        }
        .accessibilityIdentifier("modeSection")
    }

    private var modePicker: some View {
        Picker("mode.title", selection: $project.mode) {
            ForEach(AudioProjectMode.allCases) { mode in
                Text(LocalizedStringKey(mode.localizationKey)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("modePicker")
    }

    private var audioSourceSection: some View {
        ShellSection(titleKey: "section.audioSource", systemImage: "waveform.badge.plus") {
            audioSourceControls
        }
        .accessibilityIdentifier("audioSourceSection")
    }

    private var audioSourceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaceholderButton(titleKey: "audio.import", systemImage: "square.and.arrow.down")
                .accessibilityIdentifier("audioImportButton")
            PlaceholderButton(titleKey: "audio.record", systemImage: "mic")
                .accessibilityIdentifier("audioRecordButton")
            PlaceholderButton(titleKey: "audio.sample", systemImage: "waveform")
                .accessibilityIdentifier("audioSampleButton")
        }
    }

    private var playbackSection: some View {
        ShellSection(titleKey: "section.playback", systemImage: "play.circle") {
            playbackControls
        }
        .accessibilityIdentifier("playbackSection")
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaceholderButton(titleKey: "playback.original", systemImage: "play")
                .accessibilityIdentifier("playOriginalButton")
            PlaceholderButton(titleKey: "playback.processed", systemImage: "play.fill")
                .accessibilityIdentifier("playProcessedButton")
            PlaceholderButton(titleKey: "playback.stop", systemImage: "stop.fill")
                .accessibilityIdentifier("playbackStopButton")
        }
    }

    private var processingSection: some View {
        ShellSection(titleKey: "section.processing", systemImage: "gearshape.2") {
            HStack(spacing: 12) {
                Image(systemName: processingSystemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(processingLocalizationKey))
                        .font(.body)
                    if case let .processing(progress) = project.processingState {
                        ProgressView(value: progress)
                            .accessibilityIdentifier("processingProgress")
                    }
                }
            }
        }
        .accessibilityIdentifier("processingSection")
    }

    private var waveformSection: some View {
        ShellSection(titleKey: "section.waveform", systemImage: "waveform.path.ecg") {
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text("waveform.empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .accessibilityIdentifier("waveformPlaceholder")
        }
        .accessibilityIdentifier("waveformSection")
    }

    @ViewBuilder
    private var editorSection: some View {
        switch project.mode {
        case .singleModule:
            ShellSection(titleKey: "editor.singleModule.title", systemImage: "slider.horizontal.3") {
                PlaceholderEditorText(textKey: "editor.singleModule.placeholder")
            }
            .accessibilityIdentifier("singleModuleEditorSection")
        case .workflow:
            ShellSection(titleKey: "editor.workflow.title", systemImage: "square.stack.3d.up") {
                PlaceholderEditorText(textKey: "editor.workflow.placeholder")
            }
            .accessibilityIdentifier("workflowEditorSection")
        }
    }

    private var processingLocalizationKey: String {
        switch project.processingState {
        case .empty:
            "processing.empty"
        case .dirty:
            "processing.dirty"
        case .processing:
            "processing.processing"
        case .ready:
            "processing.ready"
        case .failed:
            "processing.failed"
        }
    }

    private var processingSystemImage: String {
        switch project.processingState {
        case .empty:
            "tray"
        case .dirty:
            "exclamationmark.arrow.triangle.2.circlepath"
        case .processing:
            "hourglass"
        case .ready:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}

private struct ShellSection<Content: View>: View {
    let titleKey: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(LocalizedStringKey(titleKey))
                    .font(.headline)
            } icon: {
                Image(systemName: systemImage)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PlaceholderButton: View {
    let titleKey: String
    let systemImage: String

    var body: some View {
        Button {} label: {
            HStack(spacing: 12) {
                Label(LocalizedStringKey(titleKey), systemImage: systemImage)
                Spacer(minLength: 12)
                Text("control.unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(true)
    }
}

private struct PlaceholderEditorText: View {
    let textKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(textKey))
                .foregroundStyle(.secondary)
            Label("control.unavailable", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("editorPlaceholder")
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .environmentObject(AudioProjectViewModel())
                .previewDisplayName("iPhone")

            ContentView()
                .environmentObject(AudioProjectViewModel())
                .previewDevice("iPad Pro (11-inch)")
                .previewDisplayName("iPad")
        }
    }
}
#endif
