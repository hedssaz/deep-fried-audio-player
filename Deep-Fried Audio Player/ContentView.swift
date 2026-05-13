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
    @State private var isShowingAudioExporter = false
    @State private var preparedAudioExport: PreparedAudioExport?

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
        .fileExporter(
            isPresented: $isShowingAudioExporter,
            document: preparedAudioExport?.document,
            contentType: preparedAudioExport?.contentType ?? AudioExportFormat.wav.contentType,
            defaultFilename: preparedAudioExport?.defaultFileName ?? AudioExportFormat.wav.defaultFileName()
        ) { result in
            project.completeExport(result: result)
            preparedAudioExport = nil
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

            ActionButton(
                titleKey: "audio.sample",
                systemImage: "waveform",
                accessibilityIdentifier: "audioSampleButton"
            ) {
                project.generateSampleAudio()
            }
                .disabled(project.isRecording)

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

            exportMenu

            if let exportStatusKey = project.exportStatusKey {
                Label(LocalizedStringKey(exportStatusKey), systemImage: exportStatusSystemImage(for: exportStatusKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("exportStatus")
            } else if project.canExportProcessedAudio && !project.isM4AExportAvailable {
                Label("export.m4aUnavailable", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("exportStatus")
            } else if project.canExportProcessedAudio && !project.isMP3ExportAvailable {
                Label("export.mp3Unavailable", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("exportStatus")
            }

            if let statusKey = project.playbackStatusKey {
                Label(LocalizedStringKey(statusKey), systemImage: playbackStatusSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playbackStatus")
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button {
                prepareAudioExport(.wav)
            } label: {
                Label(LocalizedStringKey(AudioExportFormat.wav.labelKey), systemImage: "waveform")
            }
            .disabled(!project.canExportProcessedAudio)
            .accessibilityIdentifier("exportWAVButton")

            Button {
                prepareAudioExport(.m4a)
            } label: {
                Label(LocalizedStringKey(AudioExportFormat.m4a.labelKey), systemImage: "waveform.badge.plus")
            }
            .disabled(!project.canExportProcessedAudio || !project.isM4AExportAvailable)
            .accessibilityIdentifier("exportM4AButton")

            Button {
                prepareAudioExport(.mp3)
            } label: {
                Label(LocalizedStringKey(AudioExportFormat.mp3.labelKey), systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(!project.canExportProcessedAudio || !project.isMP3ExportAvailable)
            .accessibilityIdentifier("exportMP3Button")
        } label: {
            Label("export.menu", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(!project.canExportProcessedAudio)
        .accessibilityIdentifier("audioExportMenu")
    }

    private var processingSection: some View {
        ShellSection(titleKey: "section.processing", systemImage: "gearshape.2") {
            Group {
                if let operationProgress = project.operationProgress {
                    OperationProgressDetailView(progress: operationProgress) {
                        Task {
                            await project.cancelActiveOperation()
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: processingSystemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(LocalizedStringKey(processingLocalizationKey))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(width: 96, height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(minHeight: 118, alignment: .topLeading)
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

    private func exportStatusSystemImage(for statusKey: String) -> String {
        switch statusKey {
        case "export.saved":
            "checkmark.circle"
        case "export.failed", "export.noProcessed", "export.unavailableWhileRecording":
            "exclamationmark.triangle"
        default:
            "info.circle"
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

    private func prepareAudioExport(_ format: AudioExportFormat) {
        Task { @MainActor in
            guard let export = await project.prepareProcessedExport(format: format) else {
                return
            }

            preparedAudioExport = export
            isShowingAudioExporter = true
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
        .accessibilityElement(children: .contain)
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
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(LocalizedStringKey(titleKey), systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct OperationProgressDetailView: View {
    let progress: OperationProgress
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(iconStyle)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(progress.titleKey))
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(LocalizedStringKey(progress.phaseKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let itemKey = progress.itemKey {
                        Text(LocalizedStringKey(itemKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let progressValue = progress.progress {
                    Text(progressValue, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .accessibilityIdentifier("processingProgressPercent")
                } else if progress.isActive {
                    ProgressView()
                        .frame(width: 44, alignment: .trailing)
                        .accessibilityIdentifier("processingIndeterminateProgress")
                } else {
                    Color.clear
                        .frame(width: 44, height: 1)
                        .accessibilityHidden(true)
                }

                progressButton
            }

            if let progressValue = progress.progress {
                ProgressView(value: progressValue)
                    .accessibilityIdentifier("processingProgress")
            } else if progress.isActive {
                ProgressView()
                    .accessibilityIdentifier("processingProgress")
            } else {
                Color.clear
                    .frame(height: 4)
                    .accessibilityHidden(true)
            }

            detailRows
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("operationProgressDetail")
    }

    @ViewBuilder
    private var progressButton: some View {
        if let progressAction = progress.action, progress.isActive {
            Button(action: action) {
                Label(
                    LocalizedStringKey(progressAction.titleKey),
                    systemImage: progressAction.systemImage
                )
                .labelStyle(.titleAndIcon)
                .frame(width: 96)
            }
            .buttonStyle(.bordered)
            .tint(progressAction == .cancel ? .red : nil)
            .accessibilityIdentifier("operationProgressActionButton")
        } else {
            Color.clear
                .frame(width: 96, height: 1)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            primaryDetailRow
                .frame(height: 18, alignment: .leading)

            terminalDetailRow
                .frame(height: 18, alignment: .leading)
        }
    }

    @ViewBuilder
    private var primaryDetailRow: some View {
        if let step = progress.step {
            Label {
                Text(verbatim: localizedStepText(step))
            } icon: {
                Image(systemName: "list.number")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("operationProgressStep")
        } else if let elapsedStartDate = progress.elapsedStartDate {
            TimelineView(.periodic(from: elapsedStartDate, by: 1)) { context in
                Label {
                    HStack(spacing: 4) {
                        Text("progress.elapsed")
                        Text(verbatim: elapsedText(from: elapsedStartDate, to: context.date))
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "timer")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("operationProgressElapsed")
            }
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var terminalDetailRow: some View {
        if let terminalState = progress.terminalState {
            Label(
                LocalizedStringKey(terminalState.labelKey),
                systemImage: terminalSystemImage(for: terminalState)
            )
            .font(.caption)
            .foregroundStyle(terminalStyle(for: terminalState))
            .accessibilityIdentifier("operationProgressTerminalStatus")
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    private var systemImage: String {
        switch progress.terminalState {
        case .completed:
            "checkmark.circle"
        case .cancelled:
            "xmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case nil:
            switch progress.kind {
            case .audioImport:
                "square.and.arrow.down"
            case .recording:
                "record.circle"
            case .playback:
                "speaker.wave.2"
            case .singleModulePreview, .workflowPreview:
                "hourglass"
            }
        }
    }

    private var iconStyle: AnyShapeStyle {
        switch progress.terminalState {
        case .completed:
            AnyShapeStyle(.green)
        case .cancelled:
            AnyShapeStyle(.secondary)
        case .failed:
            AnyShapeStyle(.red)
        case nil:
            AnyShapeStyle(.secondary)
        }
    }

    private func localizedStepText(_ step: OperationProgressStep) -> String {
        String(
            format: NSLocalizedString(step.localizationKey, comment: ""),
            step.currentValue,
            step.totalValue
        )
    }

    private func elapsedText(from startDate: Date, to currentDate: Date) -> String {
        let elapsedSeconds = max(0, Int(currentDate.timeIntervalSince(startDate)))
        let hours = elapsedSeconds / 3_600
        let minutes = (elapsedSeconds % 3_600) / 60
        let seconds = elapsedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    private func terminalSystemImage(for state: OperationProgressTerminalState) -> String {
        switch state {
        case .completed:
            "checkmark.circle"
        case .cancelled:
            "xmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private func terminalStyle(for state: OperationProgressTerminalState) -> AnyShapeStyle {
        switch state {
        case .completed:
            AnyShapeStyle(.green)
        case .cancelled:
            AnyShapeStyle(.secondary)
        case .failed:
            AnyShapeStyle(.red)
        }
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
