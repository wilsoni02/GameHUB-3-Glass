# GitHub publication checklist

## Repository metadata

- Repository name: `GameHUB-Glass`
- Description: `A fullscreen glass-style Rainmeter game launcher with local search, Steam import, artwork management, and optional Hero video.`
- Visibility: Public only for the clean source package
- Suggested topics: `rainmeter`, `rainmeter-skin`, `game-launcher`, `windows`, `desktop-customization`, `glassmorphism`, `gaming`, `launcher`, `gamehub`

Do not use the `open-source` topic. The inherited CC BY-NC-SA 3.0 license contains a non-commercial restriction and is not an OSI-approved software license.

## Initial repository upload

1. Extract the GitHub Source ZIP.
2. Upload or commit the extracted files themselves; do not make the repository a single ZIP file.
3. Confirm that `README.md`, `LICENSE.md`, `CREDITS.md`, and `THIRD_PARTY_NOTICES.md` are visible at the repository root.
4. Confirm that no `Art`, `Shortcuts`, configured library, logs, backups, or local paths are present.
5. Use an initial commit message such as `Publish GameHUB Glass 1.1.2 clean source`.

## First release

- Tag: `v1.1.2`
- Title: `GameHUB 3 (Liquid Glass) 1.1.2 — Public Clean Release`
- Asset: `GameHUB_3_Liquid_Glass_1.1.2_Clean_Install.zip`
- Also publish `SHA256SUMS.txt`.

Suggested release summary:

> First public clean release of GameHUB 3 (Liquid Glass), an unofficial non-commercial derivative of GameHUB 2. Starts with an empty library and generic UI assets. Includes local search, Home/Carousel/Grid/List views, Steam import, artwork management, and optional local Hero video. No personal paths, game art, preview videos, third-party binaries, logs, or backups are included.

Do not upload the original configured 324 MiB archive. It contains a personal game library, local paths, game artwork, preview videos, runtime diagnostics, and backups.
