# Hayn

> A free media studio for your phone. Compress, convert, trim, crop and clean your photos and videos — no subscriptions, no ads, no nagging.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev) [![Riverpod](https://img.shields.io/badge/Riverpod-2.6-3D5AFE)](https://riverpod.dev) [![Free](https://img.shields.io/badge/Free-forever-success)]() [![No ads](https://img.shields.io/badge/Ads-none-success)]()

---

## Why Hayn?

Every free media tool on the store eventually wants something from you — a subscription, an ad-watch, a paywall on the format you actually need. Hayn is the opposite stance: do the job, get out of the way, and if you want to support it, the donate button is right there. No accounts, no upsell modals, no "premium" features hidden behind a card.

It happens to run **entirely on your device** as a side effect of the design (no servers means no server bills means no subscription pressure), but the headline pitch is much simpler: it's free, and it stays free.

---

## Current status

The `bedrock` branch contains working library browsing and image operations, a Rust image core (DarkLib), and limited FFmpeg tasks for removing audio, extracting frames and creating GIFs. Image preservation and error handling still have known gaps; this is not a release claim.

| Area | Status |
|---|---|
| Library, settings, image conversion/crop/metadata tools | Implemented, with preservation defects under review |
| DarkLib / AVIF / WebP / platform HEIC bridges | Experimental integration; independent compatibility tests required |
| Remove audio / extract frames / video-to-GIF | Implemented tasks; failure-state handling needs repair |
| Surgical replacement | Removed; its old design document is historical |
| Other video/audio tools and source separation | Partial UI or planned; not complete engines |

Read [the stabilization plan](docs/12-STABILIZATION.md) for measured results and known defects, [DarkLib's bounded contract](docs/10-DARKLIB.md) for scope, and [the HDR research](docs/11-HDR-RESEARCH.md) before changing image preservation. Earlier design documents describe intended features, not completion evidence.

---

## Running locally

```bash
flutter pub get
flutter gen-l10n
flutter run
```

Android and iOS native channels exist. Host tests do not certify device compatibility; see the stabilization plan for verification limits.

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
| Persistence | `shared_preferences` (prefs) and Drift (media index) |

The current dependency is `ffmpeg_kit_flutter_new_min`; DarkLib uses Rust codecs and platform bridges. Dependency names and versions are recorded in `pubspec.yaml`, Cargo manifests and their lockfiles. Package licensing and distribution requirements must be reviewed for the actual shipped binaries; system codecs are not a blanket legal guarantee.

---

## Documentation map

The docs are split between the contributor guide (root) and the design + feature specs (in `docs/`).

| File | What's inside |
|---|---|
| [CLAUDE.md](CLAUDE.md) | The agent / contributor handbook. Read this first. Current scope, modular rules, documentation and verification requirements. |
| [docs/10-DARKLIB.md](docs/10-DARKLIB.md) | Bounded library contract, fallback and preservation policies |
| [docs/11-HDR-RESEARCH.md](docs/11-HDR-RESEARCH.md) | HDR, grids, gain maps and primary sources |
| [docs/12-STABILIZATION.md](docs/12-STABILIZATION.md) | Actual status, defects and acceptance gates |
| [docs/13-DEVELOPMENT.md](docs/13-DEVELOPMENT.md) | External development tools and local setup |
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
| [docs/features/F2-surgical-replace.md](docs/features/F2-surgical-replace.md) | Historical design for removed surgical replacement |
| [docs/features/F3-video-editing.md](docs/features/F3-video-editing.md) | Trim, crop, compress video |
| [docs/features/F4-animated-images.md](docs/features/F4-animated-images.md) | GIF / WebP / AVIF animated |
| [docs/features/F5-audio-separation.md](docs/features/F5-audio-separation.md) | ⚠️ Music / voice separation |

---

## The four non-negotiable rules

1. **Offline. Always.** No `http`, no socket, no analytics, no telemetry. Works in airplane mode.
2. **Explicit preservation.** Avoid unnecessary re-encoding; identify and validate any loss in precision, color, HDR, alpha or dimensions.
3. **User data is sacred.** Anything that touches the original goes through a verified, reversible transaction with a trash safety net.
4. **Heavy work off the main isolate.** The UI stays at 60 / 120 fps no matter what.

These are requirements; known gaps and their exit criteria are tracked in [the stabilization plan](docs/12-STABILIZATION.md). See [CLAUDE.md](CLAUDE.md) for the contributor rules.

---

## Contributing

Read [CLAUDE.md](CLAUDE.md) end-to-end. Then read the feature doc for the area you want to touch. Then write the tests and the feature together. The current exit criteria in [docs/12-STABILIZATION.md](docs/12-STABILIZATION.md) gate completion. Keep behavior, documentation and tests in the same change.

```bash
flutter analyze   # must be clean
flutter test      # must be green
```

---

## License

[GNU General Public License v3.0](LICENSE).

This is a strong copyleft license: you're free to run, study, modify, redistribute and even commercially use Hayn, but any redistributed version — including modified forks — must stay under the same GPL-3.0 license and ship its complete source. Contributors grant patent rights as part of the licence; there is no warranty.

The project policy avoids bundling x264/x265. This is a packaging policy, not a guarantee about patents or every downstream distribution.
