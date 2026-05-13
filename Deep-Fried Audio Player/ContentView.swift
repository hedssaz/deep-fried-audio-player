//
//  ContentView.swift
//  Deep-Fried Audio Player
//
//  Created by hedssaz on 2026/5/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var project: AudioProjectViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isShowingAudioImporter = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .task {
            await project.refreshPresets()
        }
        .fileImporter(
            isPresented: $isShowingAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleAudioImportResult(result)
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
            Button {
                isShowingAudioImporter = true
            } label: {
                Label("audio.import", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(project.isRecording)
                .accessibilityIdentifier("audioImportButton")

            Button {
                Task {
                    if project.isRecording {
                        await project.stopRecording()
                    } else {
                        await project.startRecording()
                    }
                }
            } label: {
                Label(
                    LocalizedStringKey(project.isRecording ? "audio.stopRecording" : "audio.record"),
                    systemImage: project.isRecording ? "stop.circle" : "mic"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(project.isRecording ? .red : nil)
                .accessibilityIdentifier("audioRecordButton")

            ActionButton(titleKey: "audio.sample", systemImage: "waveform") {
                project.generateSampleAudio()
            }
                .disabled(project.isRecording)
                .accessibilityIdentifier("audioSampleButton")

            if let statusKey = project.audioSourceStatusKey {
                Label(LocalizedStringKey(statusKey), systemImage: audioSourceStatusSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("audioSourceStatus")
            }
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
            PlaybackButton(
                titleKey: "playback.original",
                systemImage: "play",
                isActive: project.playbackState == .playingOriginal,
                isDisabled: project.originalAudioBuffer == nil || project.isRecording
            ) {
                Task {
                    await project.playOriginalAudio()
                }
            }
            .accessibilityIdentifier("playOriginalButton")

            PlaybackButton(
                titleKey: "playback.processed",
                systemImage: "play.fill",
                isActive: project.playbackState == .playingProcessed,
                isDisabled: project.processedPreviewBuffer == nil || project.isRecording
            ) {
                Task {
                    await project.playProcessedAudio()
                }
            }
            .accessibilityIdentifier("playProcessedButton")

            Button {
                project.stopPlayback()
            } label: {
                Label("playback.stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(project.playbackState == .stopped)
            .accessibilityIdentifier("playbackStopButton")

            if let statusKey = project.playbackStatusKey {
                Label(LocalizedStringKey(statusKey), systemImage: playbackStatusSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playbackStatus")
            }
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
            WaveformView(
                originalBuffer: project.originalAudioBuffer,
                processedBuffer: project.processedPreviewBuffer,
                isProcessedStale: project.processingState == .dirty
            )
        }
        .accessibilityIdentifier("waveformSection")
    }

    @ViewBuilder
    private var editorSection: some View {
        switch project.mode {
        case .singleModule:
            ShellSection(titleKey: "editor.singleModule.title", systemImage: "slider.horizontal.3") {
                SingleModuleEditorView(project: project)
            }
            .accessibilityIdentifier("singleModuleEditorSection")
        case .workflow:
            ShellSection(titleKey: "editor.workflow.title", systemImage: "square.stack.3d.up") {
                WorkflowEditorView(project: project)
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

    private var audioSourceStatusSystemImage: String {
        if project.isRecording {
            return "record.circle"
        }

        switch project.audioSourceStatusKey {
        case "audio.importFailed", "audio.recordFailed", "audio.recordPermissionDenied":
            return "exclamationmark.triangle"
        case "audio.imported", "audio.recorded":
            return "checkmark.circle"
        default:
            return "info.circle"
        }
    }

    private var playbackStatusSystemImage: String {
        switch project.playbackStatusKey {
        case "playback.playingOriginal", "playback.playingProcessed":
            return "speaker.wave.2"
        case "playback.failed", "playback.noOriginal", "playback.noProcessed", "playback.unavailableWhileRecording":
            return "exclamationmark.triangle"
        default:
            return "info.circle"
        }
    }

    private func handleAudioImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                project.audioSourceStatusKey = "audio.importFailed"
                return
            }

            Task {
                await project.importAudio(from: url)
            }
        case let .failure(error):
            project.audioSourceStatusKey = "audio.importFailed"
            project.processingState = .failed(message: error.localizedDescription)
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

private struct PlaybackButton: View {
    let titleKey: String
    let systemImage: String
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(LocalizedStringKey(titleKey), systemImage: systemImage)
                Spacer(minLength: 12)
                if isActive {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }
}

private struct ActionButton: View {
    let titleKey: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(LocalizedStringKey(titleKey), systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
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
