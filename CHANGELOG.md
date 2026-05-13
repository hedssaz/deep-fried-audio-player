# Changelog

All notable changes to Deep-Fried Audio Player should be documented in this file.

## Unreleased

### Added

- Created the Xcode SwiftUI app project for `Deep-Fried Audio Player`.
- Added project README focused on iOS/iPadOS-first product direction.
- Defined the two primary product modes: Single Module Mode and Workflow Mode.
- Documented the first effect module catalog, including bitrate reduction, low-quality codec, sample-rate reduction, filters, random frequency response, bit depth reduction, clipping, compressor, limiter, and FFT / spectral damage.
- Added `docs/IMPLEMENTATION_PLAN.md` with a phased implementation plan, architecture, model definitions, audio services, workflow engine, UI plan, persistence, permissions, testing strategy, and milestone order.
- Added the project changelog and established the rule that future changes must update it.
- Added repository hygiene ignore rules for Xcode archives, result bundles, and activity logs.
- Added localization requirements for `Localizable.xcstrings`, with default `zh-Hans` and `en` support.
- Added `docs/ARCHITECTURE.md` covering the iOS/iPadOS-first architecture, SwiftUI layering, audio data flow, rendering, processors, playback, presets, localization, and test boundaries.
- Added the Step 2 app skeleton with an `AudioProjectViewModel`, adaptive SwiftUI root shell, placeholder source/playback/waveform/editor sections, and localized `en` / `zh-Hans` string catalog entries.
- Added Step 3 core model types for `AudioBuffer`, effects, parameters, effect blocks, and workflows, plus focused model unit tests.
- Added Step 4 sample audio generation, waveform downsampling, a SwiftUI waveform view, app wiring for sample audio, and focused tests.
- Added Step 5 processing engine scaffolding with effect processors, a processor registry, cancellable workflow rendering, output safety protection, and focused renderer tests.
- Added Step 6 first real effects with editable default parameters, built-in processors for sample-rate reduction, bit-depth reduction, clipping, and limiter, localized module/parameter labels, and focused processor tests.
- Added Step 7 Single Module Mode with a real module picker, dynamic parameter editor, automatic preview rendering, JSON module preset save/load, and a send-to-workflow action.
- Added Step 8 Workflow Mode with add, duplicate, delete, enable/disable, reorder, inline parameter editing, JSON workflow preset save/load, localized workflow controls, and focused workflow tests.
- Added Step 9 Audio Import and Recording with AVFoundation file decoding, iOS/iPadOS microphone recording, visible localized source statuses, generated Info.plist microphone usage text, and focused import/recording tests.
- Added Step 10 Playback with manual original/processed playback, stop control, single-source playback coordination, localized playback statuses, and fake-controller tests that avoid producing sound.
- Added Step 11 Expanded Effects with a unified Filter / EQ module, Compressor envelope processing, Top-K Spectral Damage, mode-specific parameter visibility, localized effect controls, and focused processor/workflow tests.
- Added Step 12 Codec Capability Layer with runtime AVFoundation codec round-trip detection, AAC/MP3/Apple Lossless capability modeling, unavailable/planned codec states for AMR-NB, Speex, G.711, and G.729, real codec processors, localized codec controls, and focused capability tests.

### Changed

- Reframed the project from an earlier browser/Fourier demo direction into an Apple SwiftUI app.
- Prioritized iOS and iPadOS for v1, with macOS deferred for later evaluation.
- Replaced the default SwiftUI template screen with the localized Deep-Fried Audio Player root layout.
- Updated the default workflow renderer and single-module state to use the built-in Step 6 effect definitions.
- Replaced the single-module placeholder editor with localized controls backed by `AudioProjectViewModel`.

### Notes

- Automated testing must not trigger audio playback or produce sound.
- Current implementation is still mostly Xcode template code; product behavior is specified in documentation and implementation planning.
