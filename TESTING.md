# Release validation and Windows checklist

## Quick preview-hotfix test

1. Save/close Manager, unload **Main and Button**, merge the update, Refresh all, and load Button. Check version 1.1.1. No media reimport is needed initially.
2. Open Carousel and hover Destiny 2 without moving for a few seconds. Static should appear first, then muted video; moving off it should stop playback and return to static. Sweep cards, navigate and open Manager to confirm cancellation.
3. If the original 4K clip stays static, use Manager → Appearance to choose the optional 8-second 1080p test clip and Save. Its audio track was removed. Close Manager and try again.
4. If both stay static, copy Motion-status.ini while the failed hover is current, then unload Main and send Motion.log if present. Do not use old Manager-diagnostics.txt to diagnose a media failure.
5. Set Preview Delay to 1500 ms and check it takes effect. ReduceMotion or HeroVideo off must retain static artwork. Repeat close/reopen and a Rainmeter restart; no helper/player should remain after Main is unloaded.

Native tests are still required; Linux compilation/simulation cannot establish Windows decoding, Z-order or mouse-event delivery.

## Automated checks

Maintainer commands are in Maintenance/README.md. Checks cover strict INIs/release metadata; Lua 5.1 syntax; the fixed 24-card pool; unchanged startup/timer options; simulated all-view interaction/focus; 0–5, 15, 200 and 1000-game fixtures; rapid hover/navigation; close/reopen interruption; favorites/history/counts; manager success/failure/return; missing targets; ReduceMotion at 2560×1440 and 3840×2160.

Discovery tests cover literal punctuation/apostrophes/brackets, Unicode/partial/no matches, combined tags/Favorites/platforms, clear/restore, switching views and InputText command boundaries. Portable PowerShell helpers cover schema/tag round trips, backups, settings preservation/conflict guards, drafts, status and stale-log separation. Packaging tests cover clean-data isolation, protected update paths, reproducibility, no stale runtime files and SHA-256/CRC integrity. Image validation uses the existing repair fallback for four legacy truncated covers.

New checks also exercise the real Hub motion hooks and Lua lifecycle with delayed/stale callbacks, and compile the C# helper against .NET Framework 4.8 reference assemblies. The build environment cannot run Windows/Rainmeter. PowerShell helper execution is portable PowerShell on Linux; the Windows GDI+ artwork suite is syntax-checked only. Simulations do not establish native font metrics, frame rate or launch success.

## Motion Hero acceptance pass — Windows required

Back up the current folder, install **Update** using START_HERE.md, unload/reload both skins, then open Manager at 4K / 150%. Use a short local H.264 MP4 and transparent PNG you can recognize. No test clips are bundled.

1. **Set up four entries:** video + logo, video only, logo only, neither. Appearance → Choose preview video / Choose logo → Save game. Check both path rows and buttons are readable when scrolled into view; Save/Discard and Import Steam remain accessible. Close Manager to apply.
2. **Timing/audio:** hover a configured card or Hero area. Static should show first for at least the configured delay; video should then fade in, muted. Wait for its end: static returns and the clip does not repeatedly restart while stationary. Enable Loop and test repeat; only explicitly enabling Preview audio may produce sound. Try `PreviewStart=1` / `PreviewEnd=5` in a backed-up test entry if using trim metadata.
3. **Cancellation:** sweep rapidly between games; leave the selection before 900 ms; leave during playback; scroll repeatedly and use rapid Previous/Next. Check the focused title/logo/art/accent and launch target agree. Old callbacks must not restart the abandoned clip. Change through Home, Carousel, Grid and List during a preview. Video belongs only to the Hero; all cards remain still.
4. **Actions/lifetime:** during playback launch a known game, open Manager using each entry point, close/reopen GameHUB mid-animation, unload Main, and restart Rainmeter. Expect no separate player window, lingering audio, duplicate helper/player, black overlay or dead click area. Reopening should work. Check Windows Task Manager if a helper appears to remain after Main unload.
5. **Fallbacks:** with GameHUB unloaded, temporarily rename a cached preview, rename a logo, and try a malformed/unsupported test video. Reload: static art/title and all launch controls must work. Restore the files. On a disposable copy, rename `MotionHost.ps1` to simulate an unavailable backend; the launcher should remain functional with static art. Restore it and reload both skins.
6. **Settings:** disable Hero video, then enable it with ReduceMotion on. Neither should play video. Enable cinematic idle with ReduceMotion off: after roughly ten seconds navigation/shelves should dim subtly, while title/logo and Hero actions remain clear. Move the mouse, click, scroll or press a key: normal emphasis returns immediately. ReduceMotion disables cinematic emphasis too.
7. **Data:** verify old v1.0 entries without media still work. Choose media, Discard and confirm nothing changes; choose again, Save, move the original source and check the stored copy still works. Remove an assignment and confirm static fallback. Existing favorites, history/counts, tags, crop/accent, ordering and shortcuts must survive. On an empty clean copy, Add/Steam import still work; check a one-game library too.

For a failure, record the action sequence, view, settings, clip codec/dimensions, Windows/Rainmeter version and a short capture. A renamed/missing optional helper may leave a RunCommand entry in Rainmeter's diagnostic log; it must not produce a launcher popup or break the static layout. The backend does not create persistent media error logs.

## Focused Windows acceptance pass

1. **Install/version:** save/close Manager, unload both skins, install the chosen package, Refresh all and load Button. Check GameHUB 3, Search, All tags and the Manager version/build. Verify retained library/order/favorites/history/settings with Update.
2. **Manager contrast/layout:** at 4K/150%, inspect disabled Save/Discard/Save settings and first/last ordering buttons. Labels should be muted but readable; mouse, Space and Enter must not trigger disabled actions. Editing enables the buttons normally. Check Import Steam remains visible, all four pages fit, and dialogs have no clipped text.
3. **Interaction/discovery:** sweep over cards, scroll repeatedly, click Previous/Next rapidly, and close/reopen during motion in all four views. Hero/focus/art/Play must agree. Test a partial title, apostrophe, mixed case and no match; combine Favorites + collection + search, clear and switch views. Inspect empty shelves/results.
4. **Manager and launch:** test Manage, right-click Edit, Hero Edit and repeated startup clicks. Launcher hides only after the ready window and returns on close. Save a tag/settings change and check Library.ini.bak after a library save. Launch Steam and a local shortcut. A missing test shortcut should show feedback without recording a launch. Test Steam import with a disposable entry.
5. **Artwork/motion:** inspect configured Marathon art/frost/accent. Reframe, reset to center, Save and reopen. Malformed art should report an error and preserve prior data. Repeat with ReduceMotion and confirm motion stops at idle.
6. **Clean startup:** temporarily move your existing skin aside or use a separate Windows test account. Clean Install starts empty; Add/Import should work. Check one game and fewer than six. Restore your backed-up configured folder afterward.

Optional Windows PowerShell 5.1 helpers: `Maintenance/Test-Manager.ps1`, `Test-ControlCenter.ps1`, `Test-Artwork.ps1`, `Test-HeroMedia.ps1`, under your normal policy. They use temporary data. Keep failure messages, action steps and screenshots; use current Rainmeter logs/fresh manager diagnostics rather than treating historical logs as current errors.
