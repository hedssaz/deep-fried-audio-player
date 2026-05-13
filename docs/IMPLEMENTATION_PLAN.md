# Deep-Fried Audio Player Implementation Plan

## 1. Current State

This repository is an Xcode-generated SwiftUI app.

Current project facts:

- App target: `Deep-Fried Audio Player`
- App entry: `Deep-Fried Audio Player/Deep_Fried_Audio_PlayerApp.swift`
- Initial view: `Deep-Fried Audio Player/ContentView.swift`
- Test targets:
  - `Deep-Fried Audio PlayerTests`
  - `Deep-Fried Audio PlayerUITests`
- Product priority: iOS first, iPadOS second.
- macOS/xros support may exist in Xcode settings, but v1 implementation should not optimize for them.

The README defines the product as an iOS/iPadOS SwiftUI app with two modes:

- Single Module Mode: test one damage module quickly.
- Workflow Mode: chain multiple damage modules, reorder them, edit parameters, and save presets.

Automation must not click playback buttons or produce sound.

## 2. Product Architecture

Use a small layered architecture:

```text
SwiftUI Views
  -> ViewModels / Observable state
    -> Audio services
    -> Workflow engine
      -> Effect processors
        -> Audio buffers
```

Recommended module groups:

```text
Deep-Fried Audio Player/
  App/
  Models/
  Audio/
  Effects/
  Workflow/
  Presets/
  Views/
```

Keep the existing Xcode target. Add Swift files inside the existing app target rather than creating a Swift Package first. Package extraction can happen after the model and processor APIs stabilize.

## 3. Core Data Model

Define these model types first.

### AudioBuffer

Represents decoded mono or stereo PCM data used by processors.

Fields:

- `sampleRate: Double`
- `channelCount: Int`
- `frames: Int`
- `samples: [[Float]]`
- `duration: TimeInterval`

Rules:

- Internal processing uses `Float`.
- Multi-channel audio should be preserved when possible.
- Effects that only support mono should explicitly downmix and label the behavior.
- Every processor must return finite samples: no `NaN`, no infinity.

### EffectBlock

Represents one configurable damage module.

Fields:

- `id: UUID`
- `type: EffectType`
- `name: String`
- `isEnabled: Bool`
- `order: Int`
- `parameters: [EffectParameter]`
- `presetName: String?`

Rules:

- Every block must be reorderable.
- Disabled blocks pass audio through unchanged.
- Every block must expose editable parameters.
- Single Module Mode is represented as a temporary workflow with one enabled block.

### Workflow

Represents an ordered effect chain.

Fields:

- `id: UUID`
- `name: String`
- `blocks: [EffectBlock]`
- `createdAt: Date`
- `updatedAt: Date`

Rules:

- Blocks run from top to bottom.
- Parameter edits mark the processed preview as stale.
- Reordering blocks marks the processed preview as stale.
- Workflows must be `Codable` for local preset storage.

### EffectParameter

Use a typed enum rather than raw dictionaries.

Parameter kinds:

- `float`
- `int`
- `bool`
- `choice`
- `range`

Each parameter should include:

- stable key
- display label
- value
- allowed range or choices
- unit label, such as `Hz`, `kbps`, `dB`, `ms`, `bit`

## 4. App State and View Models

Create one top-level app model:

### AudioProjectViewModel

Responsibilities:

- Track selected product mode: single module or workflow.
- Hold original audio buffer.
- Hold processed preview buffer.
- Hold selected single module.
- Hold current workflow.
- Track processing state: idle, dirty, processing, ready, failed.
- Own playback state: stopped, playing original, playing processed.
- Expose actions for import, recording, sample generation, preview render, and stop.

Processing state enum:

```swift
enum ProcessingState {
    case empty
    case dirty
    case processing(progress: Double?)
    case ready
    case failed(message: String)
}
```

Playback state enum:

```swift
enum PlaybackState {
    case stopped
    case playingOriginal
    case playingProcessed
}
```

Keep all UI mutations on `@MainActor`. Run audio processing off the main actor.

## 5. Audio Services

### AudioImportService

Use `AVFoundation` to read user-selected files into `AudioBuffer`.

Responsibilities:

- Accept a file URL from SwiftUI file importer.
- Decode common Apple-supported formats.
- Convert decoded PCM to internal `AudioBuffer`.
- Return readable errors for unsupported files.

### RecordingService

Use `AVAudioEngine` or `AVAudioRecorder` for v1 recording.

Responsibilities:

- Request microphone permission.
- Start recording.
- Stop recording.
- Convert recorded audio to `AudioBuffer`.
- Surface permission denied and recording failure states.

### AudioPlaybackController

Use `AVAudioEngine` plus `AVAudioPlayerNode`, or `AVAudioPlayer` for a simpler v1.

Responsibilities:

- Play original buffer.
- Play processed buffer.
- Stop current playback.
- Guarantee only one source plays at a time.
- Never autoplay after import or processing.

### SampleAudioFactory

Generate deterministic sample audio for development and tests.

Requirements:

- No network access.
- No file dependency.
- Generates short audio with enough frequency content to show waveform changes.

## 6. Workflow Engine

### WorkflowRenderer

Responsible for rendering an input buffer through blocks.

Behavior:

1. Receive original `AudioBuffer` and `Workflow`.
2. Filter enabled blocks.
3. Run each block in order.
4. Clamp or normalize final output to a safe peak.
5. Return processed `AudioBuffer`.

Important rules:

- Rendering must be cancellable.
- Starting a new render cancels the previous one.
- UI should show stale output while the new render is processing, but label it as stale.
- Errors should identify the failing block.

### EffectProcessor Protocol

Each effect type maps to one processor.

Suggested shape:

```swift
protocol EffectProcessor {
    var type: EffectType { get }
    func process(_ input: AudioBuffer, block: EffectBlock) throws -> AudioBuffer
}
```

The implementation can evolve, but the core rule is stable: processors receive typed audio and typed parameters, and return a new buffer.

## 7. Effect Modules

Implement modules incrementally. Do not attempt all codec modules in the first code pass.

### Phase A Modules

These should be implemented first because they can be tested locally without external codecs:

- Sample Rate Reduction
- Bit Depth Reduction
- Clipping
- Filter / EQ, with Low-pass, High-pass, Band-pass, Notch, and Random Frequency Response modes
- Compressor
- Limiter

### Phase B Modules

Implement after the workflow engine and UI are stable:

- Spectral Damage, starting with Keep Top-K Frequency Bins

### Phase C Modules

Implement after codec capability research:

- Bitrate Reduction
- Low Quality Codec

Codec rules:

- Real encode/decode round-trip is preferred.
- If a codec is unavailable on iOS/iPadOS, show it as unavailable or planned.
- Do not simulate AMR-NB, Speex, G.711, or G.729 while labeling the output as real codec output.

## 8. UI Implementation

Design for iPhone first, then iPad.

### Root Layout

Use SwiftUI.

Suggested structure:

- iPhone: `NavigationStack` with mode switch near the top.
- iPad: `NavigationSplitView` with audio/project controls in sidebar and editor/detail on the right.

### Main Screen Sections

Top-level screen should include:

- Audio source controls: import, record, sample audio.
- Playback controls: original, processed, stop.
- Mode switch: Single Module / Workflow.
- Processing state indicator.
- Waveform comparison.

### Single Module Mode UI

Required UI:

- Module picker.
- Parameter panel for selected module.
- Preset save/load for that module.
- Button to send the current module configuration to workflow mode.
- Original vs processed waveform.

### Workflow Mode UI

Required UI:

- Add module button.
- Reorderable module list.
- Enable/disable toggle per module.
- Duplicate and delete per module.
- Inline or detail-panel parameter editor.
- Save/load workflow preset.

For iOS, module editing can push into a detail screen. For iPadOS, editing should use a side-by-side layout.

### WaveformView

Display downsampled waveform data, not all samples.

Required states:

- Empty state.
- Original waveform only.
- Original and processed waveform overlay or stacked comparison.
- Stale processed result indicator.

## 9. Persistence

Use local JSON storage for v1.

Persist:

- Module presets.
- Workflow presets.
- Last selected mode.
- Last selected module type.

Do not persist imported audio in v1 unless explicitly required later. Audio files should be imported per session.

Recommended storage:

- App documents directory for user presets.
- `UserDefaults` only for lightweight UI preferences.

## 10. iOS / iPadOS Permissions

Required permission handling:

- Microphone access for recording.
- File importer permission for audio import.

Add `NSMicrophoneUsageDescription` before implementing recording.

Error handling:

- Permission denied should be visible and recoverable.
- Unsupported audio files should show a readable error.
- Codec unavailable should appear as a module capability state, not as a crash.

## 11. Localization

Use Xcode String Catalogs from the start.

Required file:

```text
Deep-Fried Audio Player/Localizable.xcstrings
```

Rules:

- All user-visible strings must be stored in `Localizable.xcstrings`.
- Default supported languages are Simplified Chinese `zh-Hans` and English `en`.
- SwiftUI views should reference localization keys instead of hardcoded long UI text.
- Use stable semantic keys such as `home.title`, `audio.import`, `mode.singleModule`, and `workflow.addModule`.
- Error messages, permission prompts, empty states, button labels, section titles, module names, and parameter labels all count as user-visible strings.
- Short technical enum names may remain in code, but anything shown to users needs a localized display string.
- Automated UI tests should query stable accessibility identifiers where possible, not rely on localized visible text.

Acceptance:

- `Localizable.xcstrings` exists before building real UI screens.
- Initial UI shell has `zh-Hans` and `en` entries for all visible text.
- No new SwiftUI screen should introduce visible hardcoded prose.

## 12. Implementation Steps

### Step 1: Repo and Project Hygiene

- Keep README and this implementation plan in the Xcode project root.
- Ensure `.gitignore` excludes `xcuserdata`, DerivedData, `.DS_Store`, and local logs.
- Decide whether to keep Xcode's generated macOS/xros support or narrow the target later; do not spend v1 design time on macOS/xros.

Acceptance:

- `git status` shows only intentional source/doc changes.
- Xcode still opens the project.

### Step 2: App Skeleton

- Replace the default `ContentView` with a real root shell.
- Add an app-level `AudioProjectViewModel`.
- Add mode switch for Single Module / Workflow.
- Add placeholder sections for source controls, playback controls, waveform, and editor.
- Add `Localizable.xcstrings` with `zh-Hans` and `en` values for all visible placeholder UI strings.

Acceptance:

- App builds.
- iPhone preview shows a usable vertical layout.
- iPad preview shows a wider layout or split layout.
- Root shell text is loaded through `Localizable.xcstrings`.

### Step 3: Core Models

- Add `AudioBuffer`.
- Add `EffectType`.
- Add `EffectParameter`.
- Add `EffectBlock`.
- Add `Workflow`.
- Add model tests for Codable round-trip and block ordering.

Acceptance:

- Tests pass.
- Workflow presets can be represented without UI.

### Step 4: Sample Audio and Waveform

- Add `SampleAudioFactory`.
- Add waveform downsampling helper.
- Add `WaveformView`.
- Wire sample audio into the app.

Acceptance:

- Tapping sample audio generates an original buffer.
- Waveform appears.
- No playback is triggered automatically.

### Step 5: Processing Engine

- Add `WorkflowRenderer`.
- Add `EffectProcessor` protocol.
- Add a processor registry.
- Add output safety protection.
- Add cancellation for stale renders.

Acceptance:

- A workflow with zero enabled blocks returns the original audio.
- A workflow with one enabled test processor returns changed audio.
- Output has no `NaN` or infinity.

### Step 6: First Real Effects

Implement the first practical module set:

- Sample Rate Reduction
- Bit Depth Reduction
- Clipping
- Limiter

Acceptance:

- Each module has editable parameters.
- Each module changes output when parameters change.
- Unit tests verify output length and finite samples.

### Step 7: Single Module Mode

- Add module picker.
- Add parameter editor.
- Render preview when parameters change.
- Add module preset save/load.
- Add "send to workflow" action.

Acceptance:

- User can select one module and edit parameters.
- Processed waveform updates.
- Sending to workflow creates a workflow block.

### Step 8: Workflow Mode

- Add module list.
- Add add/duplicate/delete actions.
- Add enable/disable toggles.
- Add reorder behavior.
- Add workflow preset save/load.

Acceptance:

- User can build a multi-block workflow.
- Reordering changes processing order.
- Disabled blocks are bypassed.

### Step 9: Audio Import and Recording

- Add file importer.
- Decode supported audio into `AudioBuffer`.
- Add recording permission flow.
- Add recording start/stop.

Acceptance:

- Imported audio displays waveform.
- Recorded audio displays waveform.
- Permission errors are visible.

### Step 10: Playback

- Add `AudioPlaybackController`.
- Add playback of original audio.
- Add playback of processed audio.
- Add stop action.
- Ensure only one source plays at a time.

Acceptance:

- User can manually play original or processed audio.
- Stop button stops current playback.
- Automated tests do not trigger playback.

### Step 11: Expanded Effects

Add remaining non-codec modules:

- Filter / EQ as one user-facing module family with Low-pass, High-pass, Band-pass, Notch, and Random Frequency Response modes
- Compressor
- Spectral Damage first implementation: Keep Top-K Frequency Bins with `componentCount`, `windowSize`, `overlap`, `minFrequency`, `maxFrequency`, fixed phase preservation, and `mix`

Acceptance:

- Each module has parameters.
- Each module participates in workflows.
- Legacy individual filter types are not exposed as separate user-facing modules.
- Spectral Damage does not expose unimplemented dropout, smear, or generic degrade modes.

### Step 12: Codec Capability Layer

- Add codec module capability model.
- Detect or list codecs available on iOS/iPadOS.
- Implement supported real encode/decode round-trips first.
- Mark unavailable codecs as planned/unavailable.

Acceptance:

- MP3/AAC/other available codecs behave as real round-trips if implemented.
- AMR-NB, Speex, G.711, G.729 are not falsely represented if unavailable.

### Step 13: iPad Polish

- Add `NavigationSplitView` or equivalent wide layout.
- Keep workflow list visible while editing selected block.
- Improve drag/reorder target sizes.

Acceptance:

- iPad landscape is comfortable.
- iPhone portrait remains usable.

### Step 14: Test and Stabilize

- Unit tests for models, processors, renderer, presets.
- UI tests for launch, mode switch, adding module, editing parameter.
- Tests or review checks for missing localization keys on new user-visible UI.
- Manual tests for actual playback.

Acceptance:

- Automated tests pass without sound.
- Manual playback confirms deep-fried output is audible and distinct.

## 13. Test Strategy

### Unit Tests

Prioritize deterministic processor tests.

Test cases:

- Empty workflow returns unchanged buffer.
- Disabled block bypasses audio.
- Reordered blocks execute in new order.
- Parameter edits produce different output.
- Processed output length is valid.
- Processed output contains finite samples.
- Safety limiting keeps peak within configured ceiling.
- Presets encode and decode correctly.

### UI Tests

Do not tap playback buttons.

Test cases:

- Launch app.
- Switch between Single Module and Workflow mode.
- Generate sample audio.
- Add one module.
- Edit one parameter.
- Confirm processing state changes.
- Confirm waveform exists.
- Confirm user-visible text comes from localization keys where practical.

### Manual Tests

Manual only:

- Play original audio.
- Play processed audio.
- Compare audible difference.
- Record from microphone.
- Import real audio from Files.

## 14. Milestone Order

Recommended implementation order:

1. Models and placeholder UI.
2. Sample audio and waveform.
3. Workflow renderer with simple processors.
4. Single Module Mode.
5. Workflow Mode.
6. Import/recording.
7. Playback.
8. Expanded effect modules.
9. Codec capability layer.
10. iPad polish and presets.

This order avoids audio playback and codec complexity until the model, UI, and render pipeline are stable.
