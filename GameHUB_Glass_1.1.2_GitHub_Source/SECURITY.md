# Security

## Runtime behavior

The shipped runtime is local-only: it does not make web requests, require API keys, send telemetry, or create accounts. Steam import reads the local Steam registry entries, installation data, and artwork cache. GameHUB writes its own library, settings, state, artwork caches, logs, and coordination files under `GameHUBGlass\@Resources`.

The manager and optional video helper run Windows PowerShell 5.1 with `-ExecutionPolicy Bypass` for that child process. This allows the packaged local scripts to run without changing the machine's persistent execution policy. Users should still inspect scripts obtained from untrusted mirrors before running them.

Game launch targets are user-controlled. A malicious or mistaken path, URI, shortcut, or argument can execute an unintended program. Add only targets you trust.

Optional Hero video uses local files and the Windows WPF media stack. It does not stream or download media.

## Reporting a vulnerability

Use GitHub's private security-advisory feature if it is enabled for the repository. Include the affected version, reproduction steps, expected and actual behavior, and whether the issue requires a particular target, media file, or library entry. Do not publish private machine paths, library files, or logs without redacting them first.

Only the latest release is expected to receive security fixes.
