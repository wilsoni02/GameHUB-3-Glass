# Release notes

<!-- RELEASE:BEGIN -->
GameHUB 3 (Liquid Glass) **1.1.2** · Build **20260929.1** · Library schema **4** · Public Clean Release
<!-- RELEASE:END -->

## Public Clean Release

Version 1.1.2 prepares the project for a public GitHub repository, fixes fractional artwork-crop construction, and leaves the library schema unchanged.

- Adds a detailed repository README, credits, third-party notices, security guidance, contribution guidance, Git attributes, and a publication checklist.
- Corrects attribution to identify both the upstream in-skin author name, FinchNelson, and the GitHub repository author, Ethan Grant (`callmeEthan`).
- Documents the CC BY-NC-SA 3.0 declaration present in the upstream skin metadata and preserves its attribution, non-commercial, and share-alike requirements.
- Removes personal names from public metadata and test fixtures.
- Replaces configured-edition artwork notes with a public artwork policy.
- Keeps the clean package empty of library entries, user state, game art, preview videos, shortcuts, logs, diagnostics, backups, external fonts, executables, and DLLs.
- Retains deterministic manifests, per-file SHA-256 hashes, ZIP CRC validation, and source-data isolation tests.
- Preserves fractional crop coordinates when constructing `RectangleF`, keeping preview, cover, background, and frost outputs on the same framing rectangle instead of allowing one-pixel rounding drift.

No renderer, library workflow, media behavior, or data schema changes in this release beyond the artwork framing correction above.

## Included functionality

- Home shelves for recent launches, favorites, and the full matching library.
- Carousel, Grid, and List views with bounded card pools.
- Local title/tag search, platform filters, collections, custom sort, recent sort, and favorites.
- Windows Forms Manager for library entries, local Steam import, ordering, settings, appearance, and diagnostics.
- Prepared covers, backgrounds, blur caches, focal/zoom framing, and stored accents.
- Optional local Hero video and transparent PNG logos.
- Reduced-motion support and static fallbacks when optional media is missing or unsupported.
- Local-only runtime with no API key, telemetry, account system, or network artwork downloader.

## Motion Hero behavior

Schema 4 adds optional `PreviewVideo`, `PreviewStart`, `PreviewEnd`, and `Logo` fields. Old schemas load without an automatic rewrite. Explicit Manager saves write schema 4 and preserve the established backup/replacement behavior.

The optional helper uses Windows PowerShell 5.1 to compile a small C# host for one WPF `MediaElement`. It plays only local MP4/M4V/WMV files, stays below the Rainmeter Main window, does not accept clicks, and exits when Main is unloaded or Rainmeter closes. Static artwork remains visible when playback cannot start.

The helper resolves installed .NET Framework assembly locations before compilation, reports lifecycle errors to local diagnostics, and uses session/token checks to reject stale media events. Preview delay changes are dynamic. Video audio, looping, and cinematic idle are opt-in defaults in the clean package.

## Compatibility and installation

- Windows 10 or Windows 11.
- Current Rainmeter 4.5.
- Windows PowerShell 5.1 and .NET Framework 4.8.
- Best-tested layout target: 3840×2160 at 150% Windows scaling.

Clean Install replaces the skin with an empty library. Update preserves the installed `Library.ini`, `State.ini`, `Settings.ini`, Art, and Shortcuts. Save/close Manager and unload both Main and Button before either operation; see `START_HERE.md`.

## Validation completed

- Release metadata and generated banners are consistent.
- All distributable INI files parse strictly.
- Clean, update, and configured package isolation tests pass.
- Clean packaging is deterministic across repeated builds.
- Package manifests match their payloads and all ZIP entries pass CRC validation.
- The clean package contains an empty schema-4 library, default settings, empty favorites/history/launch counts, and no protected user data.
- Portable Python discovery/input tests pass.
- PowerShell helper suites and Lua interaction tests remain included for native validation.

## Validation still required on a release machine

Portable tests cannot certify actual Rainmeter rendering, Windows PowerShell 5.1 behavior, Windows Forms layout, GDI+ image processing, WPF media decoding and compositing, pointer delivery, DPI behavior, or real game launching. Before calling the release fully verified, perform the Windows acceptance checklist in `TESTING.md`, especially:

- first clean startup and empty-library behavior;
- add and local Steam import flows;
- Home/Carousel/Grid/List navigation and search;
- save/discard/backups in Manager;
- optional video startup, fallback, cancellation, and cleanup;
- 4K/150% geometry plus any additional target resolutions;
- update and rollback using a disposable configured copy.

## Known limitations

- Optional video depends on installed Windows media codecs and may add latency to the first preview.
- The UI was designed around a 4K primary monitor; other layouts need acceptance testing.
- Recently launched and launch counts describe launches dispatched by this skin, not verified process starts or external playtime.
- Steam import uses local Steam data and cached images; missing artwork receives a placeholder.
- Creative Commons licenses are unusual for software, but this derivative preserves the upstream skin's declared CC BY-NC-SA 3.0 terms.
