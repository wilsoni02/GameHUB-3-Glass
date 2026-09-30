# Release maintenance — GameHUB 3 (Liquid Glass)

Release.ini is the only editable version/build source. Product version, build and library schema are independent. Lua/PowerShell read it; the packager stamps Main/Button metadata and marked banners. Historical versions in CHANGELOG/LICENSE are not current release metadata.

From GameHUBGlass, with Python 3.9+ (maintainer tooling only):

```text
python Maintenance/release.py --stamp
python Maintenance/release.py --check
python Maintenance/release.py --package update --output ../Releases
python Maintenance/release.py --package clean --output ../Releases
# Maintainer-only configured snapshot; never publish without a privacy/art review:
python Maintenance/release.py --package personal --output ../Private-Releases
python Maintenance/Test-Release.py
python Maintenance/Test-Interactions.py --lua /path/to/lua5.1
python Maintenance/Test-DiscoveryInput.py
```

Update uses an explicit code/docs allowlist and never includes protected data. Clean uses explicit shared files and generated empty Library/State plus default Settings; no user Art/Shortcuts or arbitrary files. The maintainer-only `personal` option additionally includes existing protected data/art/shortcuts and must not be published without a separate privacy and rights review. `--package full` aliases **clean**, not a configured snapshot. Sorted entries, fixed build-date timestamps and modes make repeated packaging deterministic. Each ZIP includes SHA-256 hashes and is CRC-checked. Packaging never stamps drift silently or alters installed data.

Public GitHub releases should contain the Update and Clean Install ZIPs only. Do not merge a clean installer over a live library. No Python or extra DLL is required at runtime.

Run the native helper suite in Windows PowerShell 5.1:

```powershell
& .\Maintenance\Test-Manager.ps1
& .\Maintenance\Test-ControlCenter.ps1
& .\Maintenance\Test-Artwork.ps1
& .\Maintenance\Test-HeroMedia.ps1
```

## Disabled Manager buttons

New-Button retains a native flat WinForms Button. Its Paint handler redraws only disabled text/interior using the live client rectangle, font and padding. It never changes Enabled or enabled rendering. Muted RGB 157,177,189 text contrasts with the existing RGB 29,47,58 surface; TextRenderer handles ellipsis/clipping. Native drawing and disabled keyboard/mouse semantics still need Windows validation.

API references: [TextRenderer.DrawText](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.textrenderer.drawtext) and [Control.OnPaint](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.control.onpaint).

## Schema contract

- No migration or artwork generation runs on load or update. Existing fields retain their meanings.
- A missing `[Library] Version` is treated as the original schema 1 for compatibility.
- Schema 2 adds `Accent`, `CoverFocalX`, `CoverFocalY`, `CoverZoom`, `BackgroundFocalX`, `BackgroundFocalY`, and `BackgroundZoom`. Focal coordinates use 0..1 (default .5) and zoom uses 1..3 (default 1); Accent is RGB, with the original mint fallback.
- An explicit manager save writes schema 4, including ordinary saves, ordering/removal and Steam import. Missing framing fields get center/default values; an absent accent stays empty until artwork is processed. Older schema-1/2/3 managers reject the new marker instead of silently dropping new fields.
- Schema 3 adds optional comma-separated `Tags`. Missing means none. Explicit game saves normalize whitespace and duplicates; existing read/save/backup protections also cover tags. The fixed writer retains this field during ordering, removal and import.
- Schema 4 adds optional `PreviewVideo`, `PreviewStart`, `PreviewEnd`, `Logo`. Paths default empty; times default to full-file playback. Legacy reads never assign media or change data. The fixed writer preserves these fields on save/order/remove/import.
- The manager checks the schema before reading entries and again immediately before writing. A malformed or unsupported version raises the existing error path instead of overwriting the library or its backup.
- **Any future extension that this manager cannot round-trip must bump the library schema.** The writer still serializes a fixed field list; this pass does not add an extensible serializer for unknown fields.
- Changing `LibrarySchema` alone is not a migration. The packager rejects a schema bump until its implementation and migration plan are deliberately reviewed.
- The library writer still replaces Library.ini with a `.bak` backup on save. Status coordination is unchanged. New art caches use revision filenames; prior files remain usable for backups and are not automatically deleted. Reframing reuses an existing stored original when available, without overwriting it.

## Artwork contract

`Store-Art` is shared by manual saves and the existing local Steam import. It uses one normalized source rectangle for the 960x540 cover, 3840x2160 background and 80x45 frost input (upscaled to 1280x720). The editor preview uses that same rectangle at 480x270. Metadata is published only after the requested caches encode successfully. Manual saves stage both artwork kinds before replacing the library; failed saves restore the previous entry and remove their new files.

`Get-ArtAccent` samples a 96x54 bitmap once per saved artwork kind. It excludes transparent, nearly black/white and low-chroma pixels, groups useful hues, picks a weighted dominant group with a deterministic tie-break, and clamps its output to a readable lightness and restrained saturation. It falls back to the current mint `209,250,239`. The most recently saved kind determines the single stored accent; background wins when both are saved together. It is not called for browsing, previews or title-only saves.

Framing values are invariant-culture decimals: focal coordinates 0..1 and zoom 1..3. Missing/non-finite/malformed values use defaults; finite out-of-range values clamp. The focal point is centered where possible, then the rectangle is clamped to the source edges. At default zoom a matching 16:9 image cannot pan. Lua reads only finished image paths and a validated RGB string; it never interprets crop metadata or analyzes artwork.

## Native PowerShell check

In a Windows PowerShell 5.1 console, run `& .\Maintenance\Test-Manager.ps1` using your existing script-execution policy. The test does not change that policy or open the manager. It parses the shipped script, loads only its data/status helper functions, and uses a disposable temporary folder to test schema rejection, round trips, backups, and the status payload. It never opens your real Library.ini for writing.

Then run `& .\Maintenance\Test-Artwork.ps1`. It extracts the real artwork/save helpers without opening the manager. Synthetic images test focal pixels, crop bounds, default and extreme zoom, accent quality/fallback/determinism, cache sizes, malformed input, injected frost-write failure, a failed second image in a manual save, schema upgrade/backup, and title-only saves. All writes are in a disposable temporary folder. The GDI+ artwork tests are shipped but were not executed in the Linux build environment. The schema/status helpers and the new control-center helpers ran in portable PowerShell; neither run certifies Windows PowerShell 5.1 or Windows Forms.

The shipped manager launch commands, including their existing process-scoped ExecutionPolicy option, are unchanged. The complete runtime, actual Windows Forms window, Rainmeter integration, and game launches still need the short checklist in TESTING.md.

## Interaction regression checks

With Python 3.9+ and a Lua 5.1 executable, run:

```text
python Maintenance/Test-Interactions.py --lua /path/to/lua5.1
```

On Windows, use the path to your Lua 5.1 executable. The test uses temporary files and an in-memory Rainmeter host. It never launches games, runs the manager, or writes your real library/state/settings. It exercises action ordering, focus, navigation, hover, button states, toasts, manager callbacks, and ReduceMotion. It is separate from the native PowerShell data/schema checks above. Python and the standalone Lua executable are test tools only; the widget needs neither.

Native rendering and input delivery still require TESTING.md's Windows checklist. The desktop controller intentionally uses a short mouse-up pulse: Rainmeter's mouse-down action prevents native dragging. All fullscreen controls use held-press feedback and cancel on pointer exit.

## Control center contract

The Library and Appearance pages share one selected entry and one staged game draft. Search filters the list without replacing that draft. Explicit selection change/close asks Save, Discard or Cancel; an unsaved added game is removed on discard. The selected header borrows the existing cover preview rather than decoding thumbnails for the full list. The existing import/store/cache/backup helpers remain the processing path.

The Settings page stages its own draft. `Get-SettingRules` defines the exposed keys and their validation; `Write-ManagerSettings` patches only those keys, preserves unexposed configuration/comments/encoding, creates a `.bak`, and uses a fingerprint guard against external changes. No file is created or rewritten on read. A malformed/unsupported text encoding is reported rather than guessed. Restore defaults is a UI edit until saved. The successful manager return reloads only these exposed settings in Hub.lua; monitor geometry stays resident. Media controls extend the same rules/validation and staged saving paths.

Diagnostics label the current window/RequestId coordination separately from historical logs. Scans read a saved-library snapshot and process one target/cache per WinForms timer tick; the timer is stopped at completion, cancellation, invalidation or window close. No scan runs during initial startup. Results are timestamped snapshots and must be rerun after external changes. Existing PNG repair images count as usable with a warning; decoding uses the existing bitmap helper. URL handlers and shortcut destinations are not launched or recursively inspected.

Run `& .\Maintenance\Test-ControlCenter.ps1` in Windows PowerShell 5.1 as part of the native helper suite. It extracts real helpers, uses disposable data and lightweight control doubles, and covers settings validation/culture/encoding/preservation/backups/conflict rejection, search and draft retention, discard, accent reset, saved-data scans, stale logs/status and timer shutdown. It does not open the actual Windows Forms window. The schema/status and control-center helper tests were executed in portable PowerShell on Linux; native PowerShell 5.1 and Windows UI execution are still required. The GDI+ artwork tests remain native-only and were parsed, not run here.

The manager requests standard system-DPI awareness before controls are created, preserving any awareness mode already set by the host. The API contract is documented at https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setprocessdpiaware . It is separate from appearance; there are no DWM/acrylic effects. Validate main and modal windows at the actual 4K/150% setup; the manager does not promise per-monitor-v2 scaling across mixed-DPI monitors.

## Home and state contract

Home is the fourth saved View value. Missing/invalid saved views fall back to Home; valid older values remain unchanged. Home builds three local-data shelves in memory, using the active discovery filters while retaining custom shelf order independently of browse sort: valid History timestamps descending, Favorites in custom order, and matching games in custom order. Timestamp ties fall back to custom order and ID. Future, malformed or nonpositive timestamps do not populate Continue Playing. Calendar labels use local dates, including daylight-saving boundaries, and update on interaction/opening rather than clock polling.

State.ini has one additive optional section, `[LaunchCounts]`, with `game-id=nonnegative integer` entries. Phase 4 itself did not change Library.ini; Phase 5 adds the optional Tags field in schema 3. Missing/bad counts are unknown and not displayed; the next validated launch starts at 1. Counts increment alongside History only in the existing dispatch path, cap at 2147483647 (displayed with a plus), and are never synthesized from older timestamps. Navigation, hover, edit and invalid launch targets do not increment counts. Rainmeter's existing per-key writes preserve unrelated state. Counts measure GameHUB dispatches, not verified process starts or playtime. Removed IDs may remain in state but cannot appear on shelves without a library entry.

The same 24 card groups serve every view. Home reserves eight slots per shelf, binds only visible games, and uses no extra image caches, plugins, periodic polling or new timers. Default columns are 4/6/6; geometry can increase them to at most 8/8/8 at larger UI scales to fit the screen. Row pages are bounded and independent. Committed focus includes the shelf context so duplicate copies do not all appear selected. Page changes select a visible game through the same Hero/backdrop pipeline. Favorites and manager return rebuild these in-memory collections and retain a valid visible focus.

`Test-Interactions.py` now covers empty, 1–5, 15 and 1000-game Home fixtures; independent paging, view/filter/sort boundaries, duplicate-card focus, fast hover/Previous/Next, favorite/unfavorite, launch-count persistence and legacy fallbacks, dates and malformed history, missing targets, manager return/removal, scale limits, close/reopen interruption and ReduceMotion at 2560x1440 and 3840x2160. The mock host resets meter visibility when simulating a fresh skin and can round-trip per-key State writes entirely in memory. Existing interaction checks remain active. Native event delivery and text rendering still need the release checklist.

## Discovery and InputText contract

Discovery indexes title/tags/platform once per library load or manager return. Query matching is literal UTF-8 Unicode case folding, using a static release-time table in Discovery.lua (Unicode 14.0.0); no runtime Python/library is needed. A selected tag AND a main filter AND the query determine matching games. Home builds the same shelves from those matches and preserves custom order. Query/tag selection are resident session state; only the pre-existing State.Filter key persists the main filter. Search bookmarks retain per-view focus/page without writing files. The fixed 24 card groups and eight visible picker choices bound rendering independently of library/tag count.

Native InputText entry uses Enter to commit and FocusDismiss to cancel. A query replacement starts blank intentionally. DefaultValue and Lua callbacks must never interpolate previously typed text: Rainmeter can interpret section-variable syntax during option/argument parsing. SearchText binds InputText via `%1`; SearchCommit obtains the accepted string through GetStringValue.

InputText requires a $UserInput$ macro to display its field. Command1 therefore contains a fixed serial-number callback followed by 1025 unmatched opening brackets and the macro. Rainmeter's multibang scanner discards this unclosed tail, so input never becomes a command argument. The guard exceeds InputLimit=128 even for InputText revisions that scale that limit by a skin scale up to 8x (well above the supported desktop/skin setup). Do not shorten this guard or insert user input in Lua/bang arguments. Test-DiscoveryInput.py models this boundary with punctuation, quotes, triple quotes, bracket attacks and randomized input up to the scaled limit. It is a source-based simulation, not native InputText event certification.

Reference behavior was checked against the official Rainmeter docs and source:
- https://github.com/rainmeter/rainmeter-docs/blob/master/source/manual/plugins/inputtext.html
- https://github.com/rainmeter/rainmeter/blob/e5b132a04a27e7da40177dc9a741fb58de7a6f8e/Plugins/PluginInputText/PluginCode.cs
- https://github.com/rainmeter/rainmeter/blob/e5b132a04a27e7da40177dc9a741fb58de7a6f8e/Library/CommandHandler.cpp

InputText cannot receive focus beneath Stay Topmost. BeginSearch temporarily sets ZPos=1; commit, dismiss, close and manager reload restore ZPos=2. A serial token rejects late callbacks. Input/picker ownership blocks competing launch/hover/navigation events. Existing hover and finite animation timers are retained; typing introduces no polling. Native Enter/Escape/outside-click delivery and popup alignment still need checking on Windows.

Run `python Maintenance/Test-DiscoveryInput.py` alongside Test-Interactions.py. The latter includes 200-game/200-tag fixtures, all views, old libraries, query/filter/tag combinations, literal punctuation/Unicode, clear bookmarks, menu/input callbacks and ReduceMotion. Native PowerShell helpers also cover Tags defaulting, normalization, round trips and older-writer schema rejection. No helper writes the real installed library.

## Optional motion backend

`Motion.lua` extends the committed Hero focus without selecting games itself. A separate ActionTimer provides the default 900 ms eligibility delay; the existing 55/80 ms hover behavior is unchanged. Token/session checks reject stale media events. A finite 180 ms animation adjusts the existing backdrop alphas; the cards, frost, dim and scrim remain in Rainmeter. The hidden un-sized logo probe uses Rainmeter's decoder for text fallback; rendering remains bounded.

`MotionHost.ps1` uses a separate resource-scoped mutex and Windows PowerShell 5.1's C# compiler to host one WPF MediaElement through WinForms ElementHost. The helper sits below the exact Main HWND, does not activate or accept clicks, and uses local MP4/M4V/WMV files only. FileSystemWatcher consumes complete command snapshots (sequence/session/Complete), allowing initial open/play events to coalesce safely. Rainmeter callbacks contain internal numeric tokens only; media paths remain INI data. Stop pauses immediately; static-return completion releases the decoder. Focus/close/Manager actions restore opaque art before hiding the helper. Window-destroy and process-exit events terminate it; window-hide stops media. No per-frame file writes or periodic file polling.

Optional cinematic idle uses raw-input activity notifications only, never key values/text, while Main is open. A one-shot deadline is rescheduled for the remaining idle time; no high-frequency idle loop runs. The decoder and input listener are inactive when the launcher is closed. `@Resources/Motion-command.ini`, `Motion-status.ini`, `Motion.log` and temporary snapshots are runtime-only and excluded from every package.

Run `lua Maintenance/Test-Motion.lua` from the skin root, plus the interaction test above. `Test-HeroMedia.ps1` tests disposable local copies, immutable revisions, non-destructive removal, new defaults and (on Windows) PNG decoding/transparency. It deliberately does not launch videos or games. Native codec, Z-order/compositing, pointer input, cleanup and DPI acceptance still require TESTING.md.

Backend references: [WPF multimedia](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/graphics-multimedia/multimedia-overview), [ElementHost](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.integration.elementhost), [SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos), [Raw input](https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input). All are Windows components; no third-party plugin is bundled.

### Preview helper startup regression

`MotionHost.ps1` resolves each loaded Windows assembly to its absolute `.Location` before Add-Type compilation. Bare `*.dll` references bypass assembly-name resolution in Windows PowerShell's legacy compiler path; WPF assemblies live outside its default directory. `-LiteralPath` also supports bracketed skin paths. The WinForms WM_WINDOWPOSCHANGING handler keeps every player position/show request below Main with no activation. This supplements the existing SetWindowPos call instead of changing renderer/focus behavior.

Run `& .\Maintenance\Test-MotionHost.ps1` in Windows PowerShell 5.1 for actual installed-reference resolution and helper compilation, without playback. Portable execution covers atomic diagnostic replacement, request identity and stale-error clearing. The new status file is best-effort, single-line INI data at lifecycle events only; no per-frame writes or polling. Accepted command exceptions report immediately instead of disappearing into the duplicate-sequence guard. Runtime diagnostic files remain excluded from distributions.

Reference implementation for Windows PowerShell compiler resolution: [PowerShell legacy AddType.cs](https://github.com/PowerShell/PowerShell/blob/v6.0.0-alpha.9/src/Microsoft.PowerShell.Commands.Utility/commands/utility/AddType.cs), ResolveReferencedAssembly in the .NET Framework branch; [Add-Type documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/add-type?view=powershell-5.1).
