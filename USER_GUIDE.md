# GameHUB 3 (Liquid Glass) — User guide

See [START_HERE.md](START_HERE.md) for installation, [RELEASE.md](RELEASE.md) for changes, and [TESTING.md](TESTING.md) for Windows checks.

## Controls

| Action | Result |
| --- | --- |
| Click controller | Open fullscreen launcher |
| Mouse wheel / Previous / Next | Page the Home shelf under the pointer; navigate Carousel or scroll Grid/List rows |
| Click game | Launch immediately and hide the launcher |
| Hover game | Highlight immediately; commit the static Hero after 55 ms when navigation is settled |
| Hero Play / Favorite / Edit | Act on the game currently displayed in the Hero |
| Right-click game | Edit that entry in the manager |
| Middle-click game | Toggle favorite |
| Home / Carousel / Grid / List | Switch display mode; the choice is remembered |
| Search | Click, type a title/tag fragment, Enter to apply; Escape or outside click cancels. Click an existing query to replace it in a blank field. |
| Search x | Clear the query and restore the previous focus/page in the current view when available |
| All games / Favorites / Steam / Local / Epic | Filter all four views; Epic/Other appear when applicable |
| All tags | Choose one collection to combine with the query and main filter |
| Clear filters | Clear query, collection and main filter |
| Sort | Cycle your order, A–Z, and recently launched in Carousel/Grid/List |
| + Manage games | Add, remove, reorder, import, or edit entries |
| x | Close back toward the controller button |

Recently launched records launches through this skin. It does not read Steam playtime or launches made elsewhere. Carousel navigation loops for five or more games. Two to four entries use bounded navigation without duplicates; arrows disable at the ends. Grid/List retain focus on the visible page, choosing the nearest visible entry when paging moves it out of view.

## Home

**Continue Playing** lists games with a recorded GameHUB launch timestamp, newest first. Its larger cards show the last launch date. **Favorites** follows your custom library order, and **Your Games** follows that same custom order. Search, the main filter and the selected tag apply to all three shelves; the separate browse sort does not reorder them. Empty shelves explain how to populate them or clear discovery criteria.

Scroll over a shelf or use its own arrows to page it independently. The selected game stays visible and synchronized with the Hero, Play action, backdrop, frost and accent. A game can appear on several shelves, but only the focused copy gets the selection border. The card launch/edit/favorite shortcuts still work everywhere.

The Hero shows local calendar labels such as “Last launched today” and “Last launched yesterday”, plus recorded GameHUB launch counts when available. Older timestamps remain usable; unknown old counts are not guessed. Counts began with the first launch recorded by local launch tracking was introduced and include only validated launch requests dispatched through GameHUB. They do not confirm that a URI handler or game subsequently started, and are not Steam playtime or system-wide history. Missing/invalid local targets do not add history or counts. Launches in the same recorded second use custom order, then game ID, as a deterministic tie-break.

Home reuses the 24 existing card slots (at most eight per shelf), not one meter per installed game. At the default UI scale it shows four Continue cards and six per other shelf; at larger UI scales it fits more, smaller cards so all three shelves remain on screen. Home makes no network requests. Discovery uses the included InputText plugin.

## Game manager

The control center has four pages. The Library editor includes **Collections / tags**: optional comma-separated labels such as `Co-op, RPG`. Save normalizes spaces and duplicates; Discard retains the previous values. Multiple tags are allowed, and commas are reserved as separators. **Library** searches title/platform/target, shows the selected game's thumbnail, and edits its launch details. Searching never discards a draft; an entry outside the search stays in the editor until you choose another game. **Save game** and **Discard changes** stay visible, and unsaved edits are clearly marked. Discarding a newly added entry removes that unsaved draft.

**Appearance** contains the cover/background previews, existing Frame dialogs, focal/zoom summaries and an accent swatch. **Use default accent** stages the original mint color; Save game commits it. Choosing or reframing art afterward resumes automatic accent calculation on save. Switching Library/Appearance keeps the same draft.

**Settings** exposes scale/motion options and the optional Hero media controls below. Game edits and settings have separate Save controls; closing asks about both drafts. **Diagnostics** shows this window's startup/request status and the saved library's schema/count. Run checks scans targets and cached art one item at a time; Cancel stops the scan. Select a problem and use Open selected game to reach its editor. URL handlers and .lnk destinations are not launched or resolved. Checks are timestamped snapshots; rerun after external changes. Log timestamps/access are shown separately as history, not current errors.

The manager uses the Windows PowerShell 5.1 and Windows Forms components included with Windows. The launcher itself uses Rainmeter's included Script, ActionTimer, RunCommand and InputText components; no old HotKey, XInput, Drag&Drop, or FrostedGlass plugin is required.

- **Steam:** enter an app ID, such as `1085660`, or a `steam://rungameid/…` URL. Import Steam scans installed game manifests across Steam library folders, skips existing app IDs, and lets you choose the games to add.
- **Epic:** browse to the desktop shortcut created by Epic, or enter its game launch URL. There is no Epic library scan in this build.
- **Local programs:** browse to an EXE or a Windows `.lnk` / `.url` shortcut. EXEs get an internal Windows shortcut so optional arguments and the working folder are respected. Arguments and the working folder apply to EXE targets.
- **Artwork:** browse for or drag a PNG, JPG, or BMP onto the appropriate preview. Cover and background are independent. Originals are copied into the skin, so moving the source image afterward does not break the saved entry.
- **Framing:** choose **Frame...** beside either picker. Set horizontal/vertical focus from 0% (left/top) to 100% (right/bottom), and zoom from 100% to 300%. The preview uses the same framing as the saved image. The crop stays within the image; a matching 16:9 source needs some zoom before the focus can move it. **Reset to center** restores 50%, 50%, 100%. **Apply** stages the edit; **Save game** commits it. Cancel leaves the current framing alone.
- **Missing originals:** if an old original is missing or unreadable, Frame starts from its usable saved image at default framing and tells you. It cannot recover details already cropped out; choose the original file for that. Opening an entry or the framing dialog alone never rewrites its art.
- **Game accents:** saving artwork derives a restrained color from that framed image once. The last artwork saved determines the accent; background wins when both kinds are saved together. Old entries keep the original mint accent until artwork is saved. A title-only edit does not analyze or regenerate images.
- **Steam artwork:** import uses images that are already present in Steam's local library cache. Missing art gets a placeholder. The running manager does not download artwork or require an API key.
- **Ordering:** Move up and Move down change the custom order; clear the manager search to enable ordering. Switching entries prompts to save or discard unsaved edits. Removing an entry does not uninstall the game or delete its original files.

The launcher stays visible while the manager starts. It hides only after the editor reports a visible window. A startup failure leaves a clickable diagnostic message in the launcher. Close the manager to return to the launcher with the saved library. The previous Library.ini is kept as Library.ini.bak on a successful save.

## Motion Hero: local videos and logos

1. Select a game in **Manage games → Library**, then open **Appearance** and scroll below the artwork/accent controls.
2. Use **Choose preview video** to pick a local `.mp4`, `.m4v` or `.wmv` on your PC. Recommended: **H.264 MP4, 1920×1080, 30 FPS, 5–10 seconds**. Container extensions alone do not guarantee a supported codec. There is no trailer download, stream URL or online lookup.
3. Optionally choose a **transparent PNG logo**. A wide logo with little empty padding works best. Its aspect ratio is retained within the existing title area. Missing or undecodable logos keep the original text title.
4. **Save game** copies the selected files into `@Resources/Art/Previews` and `Art/Logos`. Videos keep their original bytes; logos are decoded and saved as a bounded transparent PNG. Moving your original file afterward does not break the saved copy. Selecting/removing media is staged until Save; Discard keeps the previous assignment. Remove clears the assignment without deleting old cached files, so backups remain useful.
5. Close Manager. Hold the pointer over the focused card or the Hero artwork for about **900 ms**. Static artwork appears first, followed by a short crossfade into the clip. The first preview in a Rainmeter session may take longer while the helper starts. Rapid hover still updates static artwork at the established fast timing; it does not start videos.

Moving to another card, leaving the selection, navigating, changing view, launching, opening Manager or closing cancels the pending/current preview. A normal pointer leave or clip end pauses the media immediately and fades back to static artwork. Focus/action changes restore static artwork immediately so the old game cannot remain onscreen. A finished clip does not restart until a new hover; Loop explicitly repeats it. Cards never play videos. Carousel offers the largest unobscured Hero area; Home/Grid/List retain their existing compact Hero and shelves.

Playback is **muted by default**. Enable Preview audio only if you want sound. **Reduce motion overrides Hero video previews and Cinematic idle mode**. The optional idle setting subdues navigation/shelves after ten seconds, keeps the Hero and actions readable, and restores normal emphasis on mouse, wheel or keyboard activity. It does not change focus or restart a finished video.

The optional backend uses Windows PowerShell 5.1, .NET Framework/WPF `MediaElement`, and installed Windows media decoders. **No WebView2 runtime, third-party Rainmeter plugin or downloaded DLL is required.** Windows editions missing their media components (including some N/KN installations), unsupported codecs, missing files, a blocked helper, or playback failure retain the static launcher. Nothing is installed automatically. Turning Hero video and Cinematic idle off leaves the static experience in use. MP4/H.264 is the recommended test format; other installed-codec support is not promised.

Advanced per-game metadata is `PreviewVideo`, `PreviewStart`, `PreviewEnd`, `Logo`. The paths may be resource-relative or absolute local paths; Manager copies selections into resource-relative caches. Optional start/end values are seconds with a dot decimal separator; blank start means zero and blank end means the natural end. Start must precede the end/duration. Invalid ranges fall back to static; exact frame-accurate trimming is not guaranteed by Windows media seeking. These values have no Manager trim UI in this release; choosing a new video clears the old range.

### If a local video remains static

Install the preview hotfix with **both Main and Button unloaded**, then Refresh all and load Button. Your existing video assignment is retained. Hover the selected card for at least 900 ms; allow up to ten seconds for the first helper startup.

For a compatibility check, choose the optional `Destiny_2_Hero_Test_1080p.mp4` from the hotfix ZIP through Manager → Appearance and Save game. It is an 8-second H.264 / 1080p / 30 FPS copy of the supplied clip without an audio track. The original saved MP4 is not changed or deleted.

If playback still does not appear, copy `@Resources/Motion-status.ini` **while the launcher is still open after the failed hover**, then unload Main and collect `@Resources/Motion.log` if present. Status has a timestamp, Session, Token and Phase; `opening` means Windows is loading/decoding, `playing` means Windows opened the clip and the helper sent the reveal callback, and `stopped` means the launcher cancelled it. `LastError` retains the last failure within that helper session until the next play attempt. A new helper startup resets prior status. The log is written by RunCommand when the helper exits, so it may be absent until then. These files do not ship with the update.

For an optional compiler-only check on Windows PowerShell 5.1, run `Maintenance/Test-MotionHost.ps1`. It uses disposable files and does not start a player or edit your library.

## Appearance and performance

The scene uses a rounded reveal from the controller position, a fullscreen game backdrop, rounded cover cards, a dark glass shelf, and short background crossfades. The glass shelf samples a pre-blurred copy of the selected game's art. This is a Rainmeter implementation, not Apple's optical refraction shader or live desktop blur.

Game color is limited to the focused/hovered card border, engaged controls, Hero Play and the shelf separator. Labels remain light and glass fills stay dark. A feathered scrim and text shadow support the Hero over bright art without increasing the whole-screen dim.

Animation uses an on-demand timer and stops after movement settles. Toast dismissal and controller click feedback use finite one-shot timers; a visible toast does not keep the animation loop running. The normal skin update interval is disabled. Hovering and scrolling do not rewrite library/settings/state or refresh the skin. If the optional media helper is active, playback lifecycle changes write a small temporary command snapshot; animation frames never write files. Only a bounded set of card meters is used; the library can contain more games than the visible slots.

The main skin stays loaded and hidden between openings. It retains some artwork memory in exchange for a faster reopening path. Game launches hide it immediately. Actual frame rate and timing depend on Windows, Rainmeter, the display, and the artwork; 16 ms timer requests are not a guaranteed refresh rate.

The Update ZIP leaves your game entries, art and launch paths unchanged. If a shortcut has moved, the launcher shows a transient message and keeps Edit available to fix its path.

## Adjustments

Open **Manage games → Settings**, adjust the values, then **Save settings** and close the manager:

| Setting | Default | Manager range |
| --- | --- | --- |
| UI scale / UIScale | 1 | 0.70–1.50 |
| Opening duration / OpenMs | 260 ms | 0–2000 ms |
| Closing duration / CloseMs | 190 ms | 0–2000 ms |
| Background fade / FadeMs | 190 ms | 0–2000 ms |
| Wheel step / WheelStep | 1 | 1–10 games in Carousel; Grid/List paging is unchanged |
| Reduce motion / ReduceMotion | Off | On / Off; also disables video and cinematic idle mode |
| Hero video previews / HeroVideo | On | On / Off; only games with a local clip can play |
| Preview delay / PreviewDelay | 900 ms | 500–5000 ms |
| Preview audio / PreviewAudio | Off | On / Off; enabling allows sound at a modest volume |
| Loop preview / PreviewLoop | Off | On / Off |
| Cinematic idle mode / HeroCinematic | Off | On / Off |
| Idle delay / CinematicDelay | 10000 ms | 5000–60000 ms |

**Restore defaults** stages these values; it does not save immediately. Invalid stored values are identified and shown as defaults without rewriting the file. Saving changes only the exposed keys, retains other sections/custom keys/comments, and keeps the prior file as Settings.ini.bak. If another editor changes the file, Reload settings before saving. Monitor width/height/position remain manual settings and still require a Main skin refresh when changed. The existing 55 ms static hover and toast delays are unchanged. Preview Delay is a separate, slower video timer.

Keep Width and Height at 0 for the main monitor. Use Rainmeter's hardware acceleration setting if it is supported and enabled on your system. No Windhawk settings are changed by this skin.

## First-run checks

1. Open and close the launcher several times. Check that it fills only the main monitor and returns to the controller position.
2. Scroll in both directions, hover different games, and try all four views.
3. Launch a Steam game, then try one of your local shortcuts.
4. Open the manager, check its fields and previews, and import or add one game.

If something is off, send a screenshot and any related entries in **Rainmeter → About → Log**. For a manager problem, include `@Resources/Manager-diagnostics.txt` and `@Resources/Manager.log`. If no diagnostic appears, unload GameHUBGlass Main and run `Manager_Diagnostic.cmd` from the GameHUBGlass folder; its console stays open so the exact error can be read.

The manager launch command uses process-scoped `-ExecutionPolicy Bypass`; it applies only to the launched process and does not change any persistent execution policy. If Windows still blocks startup, keep the exact message or diagnostic file. Browsing and launching existing entries do not depend on the manager script.

