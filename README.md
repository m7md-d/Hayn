# Hayn

> A free media studio for your phone. Compress, convert, trim, crop and clean your photos and videos — no subscriptions, no ads, no nagging.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev) [![Riverpod](https://img.shields.io/badge/Riverpod-2.6-3D5AFE)](https://riverpod.dev) [![Free](https://img.shields.io/badge/Free-forever-success)]() [![No ads](https://img.shields.io/badge/Ads-none-success)]()

---

## Why Hayn?

Every free media tool on the store eventually wants something from you — a subscription, an ad-watch, a paywall on the format you actually need. Hayn is the opposite stance: do the job, get out of the way, and if you want to support it, the donate button is right there. No accounts, no upsell modals, no "premium" features hidden behind a card.

It happens to run **entirely on your device** as a side effect of the design (no servers means no server bills means no subscription pressure), but the headline pitch is much simpler: it's free, and it stays free.

---

## What it does

| | Feature | Status |
|---|---|---|
| 📦 | **Compress + convert** images with a smart format tree (AVIF → HEIC/HEIF → WebP → JPEG) | UI complete · engine pending |
| ✂️ | **Crop, rotate, flip, strip metadata** with a custom canvas + rule-of-thirds overlay | UI complete · engine pending |
| 🩹 | **Surgical replace** — swap an original photo in-place while preserving filename, dates, GPS, metadata and album order, with a trash for safe rollback | UI complete · engine pending |
| 🎬 | **Trim video** lossless at keyframes, or smart-cut at arbitrary boundaries | UI complete · engine pending |
| 🟧 | **Crop video** with a re-encode warning and the same crop canvas | UI complete · engine pending |
| 🔇 | **Remove audio** from a video — lossless, the video stream is copied untouched | UI complete · engine pending |
| 🎞️ | **Animated images** (GIF / WebP / AVIF) from a video clip or a photo sequence | UI complete · engine pending |
| 🖼️ | **Extract frames** from a video at intervals, fps, or a single timestamp | UI complete · engine pending |
| 🎙️ | **Separate music** from voice (offline source separation via ONNX + HTDemucs) | UI complete · model pending |

All flows enforce four non-negotiable rules: no internet, no quality damage, no destructive operation without a verified backup, no heavy work on the main isolate.

---

## Project status

Hayn is in **active development**. Every screen, gesture, design token, theme, localisation pass and animation is shipping today. The actual codecs and the surgical-replace transaction are scheduled next — see [docs/05-ROADMAP.md](docs/05-ROADMAP.md) for the phase plan and exit criteria.

Today you can run the app, browse your library, navigate every flow end-to-end, and tweak every setting — but the "Save" action is currently a toast. The engines are the next phase.

---

## Running locally

```bash
flutter pub get
flutter run
```

Tested on Android (Samsung S25, API 36) and the Flutter desktop targets. iOS will follow once the native channels are wired.

---

## Stack

| Layer | Choice |
|---|---|
| Framework | Flutter (latest stable) + Dart 3 |
| State | Riverpod 2 (no `setState` for non-trivial flows) |
| Routing | `go_router` 14 with a `StatefulShellRoute` for the bottom tabs |
| Library access | `photo_manager` (offline album/asset reads) |
| Video playback | `video_player` |
| Localisation | Flutter intl + ARB (Arabic / English) with full RTL |
| Theming | Material 3 + a `HaynColors` `ThemeExtension` for tokens we own |
| Persistence | `shared_preferences` (prefs); a real DB lands with the engine phase |

Codec choices, the FFmpeg fork situation, and the platform-channel boundaries are documented in [docs/02-ARCHITECTURE.md](docs/02-ARCHITECTURE.md) and [docs/03-FORMATS.md](docs/03-FORMATS.md). **TL;DR:** the original `ffmpeg_kit_flutter` is dead (April 2025) — we ship the community fork `ffmpeg_kit_flutter_new` at LGPL, and we use the system encoders (MediaCodec / VideoToolbox) for the heavy video paths to avoid x264/x265 entirely.

---

## Documentation map

The docs are split between the contributor guide (root) and the design + feature specs (in `docs/`).

| File | What's inside |
|---|---|
| [CLAUDE.md](CLAUDE.md) | The agent / contributor handbook. Read this first. The golden rules, the stack, the surgical safety protocol. |
| [docs/01-PRD.md](docs/01-PRD.md) | Product scope, principles, success criteria |
| [docs/02-ARCHITECTURE.md](docs/02-ARCHITECTURE.md) | Layers, isolates, task queue, capabilities |
| [docs/03-FORMATS.md](docs/03-FORMATS.md) | Format decision trees + licensing reasoning |
| [docs/04-DESIGN.md](docs/04-DESIGN.md) | Design philosophy, RTL/LTR, theming, patterns |
| [docs/05-ROADMAP.md](docs/05-ROADMAP.md) | Phase plan + exit criteria |
| [docs/06-TESTING.md](docs/06-TESTING.md) | Test strategy + per-phase cases |
| [docs/07-DESIGN-SYSTEM.md](docs/07-DESIGN-SYSTEM.md) | Tokens, type, motion |
| [docs/08-COMPONENTS.md](docs/08-COMPONENTS.md) | Component catalog |
| [docs/09-SCREENS.md](docs/09-SCREENS.md) | Screen catalog + flows |
| [docs/features/F1-image-ops.md](docs/features/F1-image-ops.md) | Compress / crop / strip metadata |
| [docs/features/F2-surgical-replace.md](docs/features/F2-surgical-replace.md) | ⚠️ The surgical replace transaction (most consequential) |
| [docs/features/F3-video-editing.md](docs/features/F3-video-editing.md) | Trim, crop, compress video |
| [docs/features/F4-animated-images.md](docs/features/F4-animated-images.md) | GIF / WebP / AVIF animated |
| [docs/features/F5-audio-separation.md](docs/features/F5-audio-separation.md) | ⚠️ Music / voice separation |

---

## The four non-negotiable rules

1. **Offline. Always.** No `http`, no socket, no analytics, no telemetry. Works in airplane mode.
2. **No quality damage.** Never re-encode unless absolutely necessary, and never twice.
3. **User data is sacred.** Anything that touches the original goes through a verified, reversible transaction with a trash safety net.
4. **Heavy work off the main isolate.** The UI stays at 60 / 120 fps no matter what.

These aren't aspirations — they're enforced at the architecture level. See [CLAUDE.md](CLAUDE.md) for the full rules.

---

## Contributing

Read [CLAUDE.md](CLAUDE.md) end-to-end. Then read the feature doc for the area you want to touch. Then write the tests and the feature together. The exit criteria in [docs/05-ROADMAP.md](docs/05-ROADMAP.md) gate the phases — don't claim a phase complete before the cases in [docs/06-TESTING.md](docs/06-TESTING.md) pass.

```bash
flutter analyze   # must be clean
flutter test      # must be green
```

---

## License

Source is open. Final license decision lives in [docs/03-FORMATS.md](docs/03-FORMATS.md) (it's tied to the encoder choices). Until then, treat the code as source-available, attribution-required, no commercial redistribution.
