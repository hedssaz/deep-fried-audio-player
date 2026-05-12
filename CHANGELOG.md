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
- Added the Step 2 app skeleton with an `AudioProjectViewModel`, adaptive SwiftUI root shell, placeholder source/playback/waveform/editor sections, and localized `en` / `zh-Hans` string catalog entries.

### Changed

- Reframed the project from an earlier browser/Fourier demo direction into an Apple SwiftUI app.
- Prioritized iOS and iPadOS for v1, with macOS deferred for later evaluation.
- Replaced the default SwiftUI template screen with the localized Deep-Fried Audio Player root layout.

### Notes

- Automated testing must not trigger audio playback or produce sound.
- Current implementation is still mostly Xcode template code; product behavior is specified in documentation and implementation planning.
