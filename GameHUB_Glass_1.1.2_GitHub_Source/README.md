# GameHUB 3 (Liquid Glass)

GameHUB 3 (Liquid Glass) is a fullscreen game launcher for Rainmeter. It provides a controller button, four library views, local search and collections, a Windows control center, prepared artwork support, and optional local Hero video previews.

This is an unofficial, non-commercial derivative of [GameHUB 2](https://github.com/callmeEthan/GameHUB2) by FinchNelson / Ethan Grant (`callmeEthan`). It is not affiliated with or endorsed by the original author, Rainmeter, Valve, Microsoft, or any game publisher.

Current release: **1.1.2** · Build **20260929.1** · Library schema **4**

## Highlights

- Home shelves for recently launched games, favorites, and the full library.
- Carousel, Grid, and List views backed by a single local library.
- Title and tag search, platform filters, collections, custom ordering, and launch history.
- Steam library import from local Steam data; no API key or network scraper is required.
- Windows Forms manager for games, artwork, appearance, settings, and diagnostics.
- Prepared covers, backgrounds, blur caches, focal positioning, zoom, and stored accents.
- Optional local MP4/M4V/WMV Hero previews and transparent PNG logos.
- Reduced-motion option and static fallbacks when optional media cannot play.
- No bundled plugin DLLs, external fonts, online services, telemetry, or account system.

## Requirements

- Windows 10 or Windows 11.
- A current Rainmeter 4.5 installation.
- Windows PowerShell 5.1 and .NET Framework 4.8 for the manager and optional video helper.
- Steam only if you want to use local Steam import or `steam://` launch targets.

The interface was developed primarily for a 4K display at 150% Windows scaling. Other resolutions are supported through `UIScale`, but should be tested on the intended monitor.

## Clean installation

Use the release asset named `GameHUB_3_Liquid_Glass_1.1.2_Clean_Install.zip`. Do not install the repository source ZIP as though it were a release package.

1. Close Game Manager.
2. In Rainmeter, unload both `GameHUBGlass\Main` and `GameHUBGlass\Button` if either is active.
3. If an older `GameHUBGlass` folder exists, move it somewhere outside the Rainmeter `Skins` directory as a backup.
4. Extract the release ZIP. Copy its `GameHUBGlass` folder directly into the Rainmeter `Skins` directory. Avoid creating a nested `GameHUBGlass\GameHUBGlass` folder.
5. In Rainmeter, select **Refresh all**.
6. Load `GameHUBGlass\Button\Button.ini`.
7. Click the controller, open **Manage games**, then choose **+ Add game** or **Import Steam**.

The clean package starts with an empty library, default settings, empty favorites/history, and only generic UI artwork. It contains no personal paths, shortcuts, game art, preview videos, logs, backups, or runtime status files.

## Updating an existing installation

Back up the entire installed `GameHUBGlass` folder first. Save and close Manager, unload both Main and Button, merge the code-only update over the existing folder, select **Refresh all**, then load Button again. Do not replace a configured installation with the clean package unless you intentionally want an empty library.

See [START_HERE.md](START_HERE.md) for the complete installation and recovery procedure.

## Using the launcher

- Click the desktop controller to open the launcher.
- Click a game to launch it.
- Right-click a game to edit it; middle-click toggles Favorite.
- Use Home, Carousel, Grid, or List to change views.
- Search matches titles and tags locally.
- Use Manager's Appearance page to choose and frame local artwork, preview video, or a transparent logo.

See [USER_GUIDE.md](USER_GUIDE.md) for all controls and configuration details.

## Local data and privacy

GameHUB stores its library, settings, favorites, history, launch counts, cached artwork, and optional media under `GameHUBGlass\@Resources`. Steam import reads the local Steam installation and artwork cache. The shipped runtime performs no web requests and requires no API key.

Launch targets are user-controlled and may execute programs or URI handlers. Only add paths and commands you trust. The manager and motion helper run local PowerShell scripts with a process-scoped execution-policy override; they do not change the machine's persistent PowerShell policy. See [SECURITY.md](SECURITY.md).

## Repository layout

```text
@Resources/        Runtime scripts, defaults, and generic UI assets
Button/            Desktop controller skin
Main/              Fullscreen launcher skin
Maintenance/       Release builder and regression tests
README.md          Project overview and installation
START_HERE.md      Detailed install/update/recovery steps
USER_GUIDE.md      Controls and configuration
RELEASE.md         Current release notes and validation limits
CHANGELOG.md       Version history
LICENSE.md         License scope and attribution requirements
```

Generated or personal content does not belong in Git history. In particular, do not commit a configured library, artwork cache, shortcuts, videos, logs, diagnostics, status files, or backups.

## Development and validation

The running skin needs neither Python nor a standalone Lua interpreter. Those tools are used only by maintainers.

```powershell
python Maintenance\release.py --check
python Maintenance\Test-Release.py
python Maintenance\Test-DiscoveryInput.py
```

Additional Windows PowerShell and Lua checks are listed in [TESTING.md](TESTING.md) and [Maintenance/README.md](Maintenance/README.md). Native Rainmeter rendering, Windows media playback, DPI behavior, and input delivery still require manual Windows acceptance testing.

## Release packaging

To create a deterministic empty-library package:

```powershell
python Maintenance\release.py --package clean --output <folder-outside-this-project>
```

The builder uses an explicit allowlist, generates clean data files, excludes runtime/private artifacts, records SHA-256 hashes in `RELEASE_MANIFEST.json`, and verifies the ZIP CRC. Packaging does not modify the installed library.

## Credits and license

GameHUB Glass is based on GameHUB 2 by FinchNelson / Ethan Grant. Major changes include a replacement fullscreen interface, local library manager, search/tags/collections, prepared artwork pipeline, release tooling, tests, and optional local media support. Development included OpenAI-assisted code and documentation review.

The upstream skin metadata identifies **Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported**. This derivative follows the same terms. Commercial use is not permitted, attribution is required, and adaptations must use the same license. See [LICENSE.md](LICENSE.md), [CREDITS.md](CREDITS.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Game names, logos, and artwork belong to their respective owners. They are intentionally absent from the public clean package.

## Project status

This is a community project, not an official GameHUB sequel. The optional video layer depends on Windows media codecs and may fall back to static artwork. Review [RELEASE.md](RELEASE.md) before publishing or reporting a release as fully validated.
