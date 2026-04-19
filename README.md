# PulseBeat (Offline Metronome MVP)

Flutter-based offline metronome MVP for Web, Windows, and mobile (Android/iOS).

## MVP Scope

- Main metronome page
  - BPM range `20-240`, step `1`, plus/minus and direct input
  - Time signatures: `2/4`, `3/4`, `4/4`, `6/8`
  - Subdivisions: none / 8th / 16th / triplet
  - Accent matrix per beat: strong / normal / mute
  - Play/Pause, visual beat indication
  - TAP tempo (4-8 recent taps, reset after 2 seconds idle)
- Presets page
  - Save current config as local preset
  - List, load, delete presets
  - Recent usage sorting
- Settings page
  - Volume, tone
  - Default BPM / time signature / subdivision
  - Dark theme
  - Visual hints toggle
  - Clear local data

## Technical Notes

- Offline-first: no network or account dependency.
- Persistence: `shared_preferences`.
- Metronome click audio: generated local WAV samples + `audioplayers`.
- Single Flutter codebase used across Web/Windows/mobile.

## Project Structure

- `lib/main.dart`: app entry
- `lib/src/app.dart`: root state + theme
- `lib/src/pages/`: main/presets/settings UI + navigation shell
- `lib/src/metronome_engine.dart`: timer + click playback engine
- `lib/src/models.dart`: domain models and constants
- `lib/src/storage.dart`: local persistence service
- `test/widget_test.dart`: basic widget flow test

## CI / Multi-platform Packaging

Repository workflows already include build/release pipelines for Web, Windows, Android, iOS, and macOS under `.github/workflows/`.
