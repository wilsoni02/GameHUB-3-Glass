# GameHUB 3 (Liquid Glass)

<!-- RELEASE:BEGIN -->
GameHUB 3 (Liquid Glass) **1.1.2** · Build **20260929.1** · Library schema **4** · Public Clean Release
<!-- RELEASE:END -->

GameHUB is a fullscreen Rainmeter game launcher with Home shelves, Carousel, Grid and List views; local search and collections; prepared artwork; and a Windows Forms control center. The skin folder remains named `GameHUBGlass` to preserve its established Rainmeter configuration identity.

## Choose the correct package

| Package | Use it for | Data behavior |
| --- | --- | --- |
| **Clean Install ZIP** | A new public installation | Empty library, empty favorites/history, default settings, generic UI assets only. |
| **Update ZIP** | Upgrading an existing configured installation | Omits library, settings, state, artwork and shortcuts so installed data is retained. |
| **GitHub Source ZIP** | Reviewing or contributing to the source | Repository files; not arranged as a direct installer. |

Do not merge Clean Install over a configured installation unless you intentionally want to replace its library and settings.

## Clean installation

1. Save and close Game Manager.
2. In Rainmeter, unload both `GameHUBGlass\Main` and `GameHUBGlass\Button`. Closing the fullscreen launcher alone can leave Main loaded with old code.
3. If `GameHUBGlass` already exists, move the entire folder outside the Rainmeter `Skins` directory as a backup.
4. Extract the Clean Install ZIP.
5. Copy its single `GameHUBGlass` folder directly into Rainmeter's `Skins` directory. Do not nest it inside another `GameHUBGlass` or `GameHUB2` folder.
6. In Rainmeter, choose **Refresh all**, then load `GameHUBGlass → Button → Button.ini`.
7. Click the controller and choose **Manage games → Library → + Add game** or **Import Steam**.

The clean package has no personal entries, local paths, shortcuts, game artwork, videos, logs, diagnostics, backups, or runtime status files.

## Updating while preserving a library

1. Save and close Manager.
2. Unload both Main and Button.
3. Back up the complete installed folder outside Rainmeter `Skins`.
4. Extract the Update ZIP outside `Skins`.
5. Merge its `GameHUBGlass` folder into the existing installation and replace matching files. Do not delete the existing folder first.
6. Choose **Refresh all** and reload Button.
7. Open the launcher and confirm the version shown by Manager.

The update package deliberately omits `Library.ini`, `State.ini`, `Settings.ini`, Art, Shortcuts, backups, logs, and runtime coordination files.

## Requirements

- Windows 10 or Windows 11.
- A current Rainmeter 4.5 installation.
- Windows PowerShell 5.1 and .NET Framework 4.8.
- Steam only for local Steam import and Steam launch targets.

No Python installation, API key, third-party Rainmeter plugin, external font, or bundled executable is required at runtime. Optional video uses the local Windows WPF media stack and installed codecs. Missing or unsupported media falls back to static artwork. Cinematic idle and preview audio are off by default in Clean Install.

The PowerShell manager and helper use a process-scoped execution-policy option. They do not persistently change the system policy. See `SECURITY.md` for the runtime security model.

## Recovery

If Search, tags, or the new version do not appear after an update, unload both skins, merge the update again, choose **Refresh all**, and load Button. Refreshing the skin list without unloading old Main code is insufficient.

To roll back, close Manager, unload both skins, move the new folder aside, restore the complete backup, choose **Refresh all**, and load Button. Restoring the whole backup also restores its library, settings, state, and artwork to the backup date.

Schema 4 adds optional preview-video, trim, and logo fields. Older libraries load without automatic rewriting. An explicit save from the current Manager writes schema 4; older managers should not write a schema-4 library.

## Documentation

- [README.md](README.md): project overview, features, installation, privacy, and release packaging.
- [USER_GUIDE.md](USER_GUIDE.md): controls, Manager, artwork, settings, and troubleshooting.
- [RELEASE.md](RELEASE.md): current changes and validation limits.
- [CHANGELOG.md](CHANGELOG.md): consolidated history.
- [TESTING.md](TESTING.md): Windows acceptance checklist.
- [SECURITY.md](SECURITY.md): local execution and reporting guidance.
- [LICENSE.md](LICENSE.md), [CREDITS.md](CREDITS.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): attribution and licensing.
- [Maintenance/README.md](Maintenance/README.md): release tools and technical contracts.
