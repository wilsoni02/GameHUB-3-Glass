# Artwork sources and policy

The public clean package contains only generic interface assets required to render the launcher:

```text
@Resources/UI/Backdrop.jpg
@Resources/UI/Blur.jpg
@Resources/UI/Controller.png
@Resources/UI/Placeholder.png
@Resources/UI/Vignette.png
```

`Controller.png` is adapted from controller artwork associated with the original GameHUB 2 skin and is distributed under the project's inherited CC BY-NC-SA 3.0 terms. The remaining files are generic project UI assets; none depicts a specific commercial game.

The public source and clean installer intentionally exclude:

- game covers and backgrounds;
- original high-resolution game art;
- generated game-art caches and repairs;
- preview videos and game logos;
- shortcuts and machine-specific launch targets;
- external fonts, plugin binaries, and thumbnail executables.

Users may add local artwork and media through Manager. Those user-provided files remain the responsibility of the user and are not licensed by this project. Do not commit them to a public fork unless you have redistribution rights and document the source and license.

Game names, logos, artwork, and trademarks remain the property of their respective owners.
