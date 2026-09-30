# Changelog — GameHUB 3 (Liquid Glass)

## 1.1.2 — Public Clean Release

Prepare a repository-safe public distribution with no schema change. Add a detailed README, credits, third-party notices, security and contribution guidance, Git hygiene, and a publication checklist. Correct upstream attribution and explain the inherited CC BY-NC-SA 3.0 declaration. Remove personal names from metadata and test fixtures. Replace configured artwork notes with a public artwork policy. Fix `RectangleF` construction so fractional artwork framing is preserved consistently across preview, cover, background, and frost outputs. Clean packaging continues to exclude user data, game media, shortcuts, runtime artifacts, binaries, and fonts while retaining deterministic manifests, SHA-256 hashes, CRC checks, and isolation tests.

## 1.1.1 — Hero preview hotfix

Resolve installed WPF/WinForms compiler references to absolute DLL locations for Windows PowerShell. Keep the player below Main during every native positioning request, including WinForms Show, to protect hover ownership. Honor changed preview delays through dynamic measure options. Add session-tagged startup/playback diagnostics with actual failure details; reset prior errors on a new attempt. No library, settings, video, artwork, Manager or focus-model changes.

## 1.1.0 — Motion Hero Update

Optional local Hero video previews after 900 ms of uninterrupted focus/hover, muted by default, with static-first crossfades and cancellation on leave, navigation, launch, Manager and close. Optional transparent PNG Hero logos. Appearance gains staged local media selection/removal; Settings gains video controls and opt-in cinematic idle emphasis. An optional Windows WPF media helper supplies playback without a third-party Rainmeter plugin. Missing media, codecs or helper support falls back to the existing static Hero. Schema 4 preserves per-game video/logo/trim metadata; old libraries load unchanged. User data and the established launcher/Manager/artwork flows are preserved.

## 1.0.0 — First release

New public name, readable disabled Manager buttons, complete documentation, explicit unload/update steps and isolated configured/update/clean distributions. Library schema stays 3. Current build identity and details are in RELEASE.md.

## Verified development milestones

| Milestone | Main changes |
| --- | --- |
| Phase 5 / 0.1.10 | Local title/tag search, Unicode matching, Favorites/platform filters, collections and schema 3; bounded rendering across all four views. |
| Phase 4 | Home shelves: Continue Playing, Favorites, Your Games; local launch counts beside timestamps. |
| Phase 3 and layout fix | Library/Appearance/Settings/Diagnostics control center; draft handling, validation, previews and integrated settings; Import Steam/ordering reserved rows and improved 150% layout. |
| Phase 2 | Stored artwork accents, focal/zoom framing, prepared caches and restrained Hero readability; schema 2. |
| Phase 1 | Deterministic focus/Hero synchronization, Play/Favorite/Edit alternatives, control states and transient feedback. |
| Phase 0 / 0.1.4 | Central release metadata, packager, runtime-file hygiene and schema protection. |
| 0.1.3 | PowerShell 5.1 status-file compatibility; best-effort status writes; safe image replacement; rapid-hover flash fix. |
| 0.1.2 | Process-scoped execution-policy launch fix, immediate hover highlight, 55 ms preview. |
| 0.1.1 | Visible-manager handshake, duplicate-start protection, timeout/diagnostics, legacy cover repairs and centered major controls. |
| 0.1.0 | Initial GameHUB Glass fullscreen launcher, controller, local editor and prepared art based on the GameHUB 2 collection. |

Unrecorded intermediate version numbers are not guessed. Original attribution remains in LICENSE.md.

The Phase 5 report of missing Search/tags was resolved by unloading both skins and reloading the verified files. No different discovery implementation was needed. START_HERE.md now makes that sequence explicit.
