#!/usr/bin/env python3
"""Stamp/check release metadata and package an explicit data-preserving update.

Python 3.9+, standard library only. Not used by the running skin.
"""
import argparse
import configparser
import hashlib
import json
from datetime import datetime
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
UPDATE_FILES = (
    "README.md",
    "CREDITS.md",
    "THIRD_PARTY_NOTICES.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "@Resources/Release.ini",
    "@Resources/Scripts/Hub.lua",
    "@Resources/Scripts/Discovery.lua",
    "@Resources/Scripts/Motion.lua",
    "@Resources/Scripts/MotionHost.ps1",
    "@Resources/Scripts/MotionHost.cs",
    "@Resources/Scripts/Manager.ps1",
    "Main/Main.ini",
    "Button/Button.ini",
    "START_HERE.md",
    "RELEASE.md",
    "USER_GUIDE.md",
    "CHANGELOG.md",
    "TESTING.md",
    "ARTWORK_SOURCES.md",
    "LICENSE.md",
    "Manager_Diagnostic.cmd",
    "Maintenance/README.md",
    "Maintenance/release.py",
    "Maintenance/Test-Interactions.py",
    "Maintenance/Test-DiscoveryInput.py",
    "Maintenance/Test-Manager.ps1",
    "Maintenance/Test-Artwork.ps1",
    "Maintenance/Test-ControlCenter.ps1",
    "Maintenance/Test-Release.py",
    "Maintenance/Test-Motion.lua",
    "Maintenance/Test-HeroMedia.ps1",
    "Maintenance/Test-MotionHost.ps1",
)
SHARED_FILES = UPDATE_FILES + (
    "@Resources/Scripts/Button.lua",
    "@Resources/UI/Backdrop.jpg",
    "@Resources/UI/Blur.jpg",
    "@Resources/UI/Controller.png",
    "@Resources/UI/Placeholder.png",
    "@Resources/UI/Vignette.png",
)
DATA_FILES = ("@Resources/Library.ini", "@Resources/State.ini", "@Resources/Settings.ini")


def ini(path):
    parser = configparser.RawConfigParser(strict=True, interpolation=None)
    parser.optionxform = str
    with path.open(encoding="utf-8-sig") as stream:
        parser.read_file(stream)
    return parser


def release():
    data = dict(ini(ROOT / "@Resources/Release.ini")["Release"])
    if not re.fullmatch(r"\d+\.\d+\.\d+", data["Version"]):
        raise ValueError("Release Version must be major.minor.patch")
    if not re.fullmatch(r"\d{8}\.\d+", data["Build"]):
        raise ValueError("Build must be YYYYMMDD.sequence")
    if data["LibrarySchema"] != "4":
        raise ValueError("This release reads library schemas 1/2/3/4 and writes 4; a schema bump needs code and migration review")
    return data


def expected_texts(data):
    for name in ("Main/Main.ini", "Button/Button.ini"):
        path = ROOT / name
        raw = path.read_bytes().decode("utf-8")
        newline = "\r\n" if "\r\n" in raw else "\n"
        text = raw.replace("\r\n", "\n")
        match = re.search(r"(?m)^\[Metadata\]\n([^\[]*)", text)
        if not match:
            raise ValueError("Missing Metadata section: " + name)
        metadata = match.group(1)
        # Only these generated keys are touched; all other settings stay intact.
        metadata, count = re.subn(r"(?m)^Version=.*$", "Version=" + data["Version"], metadata)
        if count != 1:
            raise ValueError("Expected one Metadata Version: " + name)
        metadata = re.sub(r"(?m)^Build=.*\n", "", metadata)
        metadata = metadata.replace("Version=" + data["Version"] + "\n",
                                    "Version=" + data["Version"] + "\nBuild=" + data["Build"] + "\n", 1)
        text = text[:match.start(1)] + metadata + text[match.end(1):]
        yield path, text.replace("\n", newline).encode("utf-8")
    banner = ("<!-- RELEASE:BEGIN -->\n"
              "GameHUB 3 (Liquid Glass) **{Version}** · Build **{Build}** · Library schema **{LibrarySchema}** · {Name}\n"
              "<!-- RELEASE:END -->").format(**data)
    for name in ("START_HERE.md", "RELEASE.md"):
        path = ROOT / name
        text = path.read_text(encoding="utf-8")
        text, count = re.subn(r"<!-- RELEASE:BEGIN -->.*?<!-- RELEASE:END -->", banner, text, flags=re.S)
        if count != 1:
            raise ValueError("Expected one generated release banner: " + name)
        yield path, text.encode("utf-8")


def check(data):
    drift = [str(path.relative_to(ROOT)) for path, expected in expected_texts(data)
             if path.read_bytes() != expected]
    if drift:
        raise ValueError("Version/build drift: " + ", ".join(drift) + "; run --stamp")
    for name in ("@Resources/Scripts/Hub.lua", "@Resources/Scripts/Manager.ps1"):
        text = (ROOT / name).read_text(encoding="utf-8-sig")
        if "Release.ini" not in text or re.search(r"\b\d+\.\d+\.\d+\b", text):
            raise ValueError("Runtime release information must come from Release.ini: " + name)
    for path in ROOT.rglob("*.ini"):
        if distributable(path.relative_to(ROOT)):
            ini(path)
    for name in SHARED_FILES:
        path = Path(name)
        if not (ROOT / path).is_file() or protected(path) or not distributable(path):
            raise ValueError("Invalid update file: " + name)


def protected(path):
    p = path.as_posix().lower()
    return (p in {"@resources/library.ini", "@resources/state.ini", "@resources/settings.ini"}
            or p.startswith(("@resources/art/", "@resources/shortcuts/")))


def distributable(path):
    p = path.as_posix().lower()
    name = path.name.lower()
    return not (any(part.startswith(".") or part == "__pycache__" for part in path.parts)
                or p.startswith("@resources/manager-")
                or p.startswith("@resources/manager.")
                or p.startswith("@resources/motion-")
                or name.endswith((".log", ".bak", ".new", ".tmp", ".pyc", ".zip"))
                or name in {"thumbs.db", "desktop.ini"})


def clean_defaults(data):
    return {
        "@Resources/Library.ini": "[Library]\nVersion=" + data["LibrarySchema"] + "\n",
        "@Resources/State.ini": "[State]\nView=home\nSort=custom\nFilter=all\nLastId=\n\n[Favorites]\n\n[History]\n\n[LaunchCounts]\n",
        "@Resources/Settings.ini": "; Width/Height 0 uses the primary monitor. Use Manager > Settings for scale/motion.\n[Settings]\nWidth=0\nHeight=0\nUIScale=1\nOpenMs=260\nCloseMs=190\nFadeMs=190\nWheelStep=1\nReduceMotion=0\nHeroVideo=1\nPreviewDelay=900\nPreviewAudio=0\nPreviewLoop=0\nHeroCinematic=0\nCinematicDelay=10000\n",
    }


def package(kind, output, data):
    check(data)  # Never silently stamp a release during packaging.
    if kind == "full":
        kind = "clean"
    names = set(UPDATE_FILES if kind == "update" else SHARED_FILES)
    if kind == "personal":
        for name in DATA_FILES:
            if not (ROOT / name).is_file():
                raise ValueError("Personal snapshot needs " + name)
        names.update(p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*")
                     if p.is_file() and protected(p.relative_to(ROOT)) and distributable(p.relative_to(ROOT)))
    payload = {"GameHUBGlass/" + name: (ROOT / name).read_bytes() for name in sorted(names)}
    if kind == "clean":
        payload.update({"GameHUBGlass/" + name: value.encode("utf-8")
                        for name, value in clean_defaults(data).items()})
    title = "GameHUB 3 (Liquid Glass) {Version} / build {Build}".format(**data)
    if kind == "update":
        install = ("UPDATE FOR THE VERIFIED STABLE SKIN\n"
                   "Save/close Manager. Right-click controller: Unload launcher and button.\n"
                   "Closing the launcher alone leaves old Main code loaded. Unload BOTH skins.\n"
                   "Back up your current folder outside Rainmeter Skins.\n"
                   "Merge this GameHUBGlass folder into the existing skin folder; replace matching files.\n"
                   "Do not delete or replace the whole existing folder.\n"
                   "Refresh all in Rainmeter, then load Button/Button.ini.\n"
                   "This update omits Library.ini, State.ini, Settings.ini, artwork, shortcuts, backups, and runtime logs/status.\n")
    elif kind == "clean":
        install = ("CLEAN INSTALL - EMPTY LIBRARY\n"
                   "Do not merge over an existing library. Use Update to preserve it.\n"
                   "Save/close Manager, unload Main AND Button, and keep a backup outside Skins.\n"
                   "Copy GameHUBGlass into Rainmeter Skins. Refresh all, then load Button/Button.ini.\n"
                   "Choose Manage games > Library > Add / Import Steam.\n"
                   "No personal entries, art, shortcuts, history, favorites or runtime artifacts.\n")
    else:
        install = ("CONFIGURED SNAPSHOT - FOR THE MACHINE THAT CREATED IT\n"
                   "Contains configured library, settings, state, artwork and shortcuts.\n"
                   "Save/close Manager, unload Main AND Button, and move the old folder to a backup outside Skins.\n"
                   "Copy this complete GameHUBGlass folder into Skins; Refresh all, load Button/Button.ini.\n"
                   "Use Update if your library has changed since the supplied snapshot.\n"
                   "Runtime logs, status files, backups and temporary files are omitted.\n")
    readme = title + "\n\n" + install + "\nRead GameHUBGlass/RELEASE.md for changes, validation limits, and the Windows checklist.\n"
    output.mkdir(parents=True, exist_ok=True)
    suffix = {"update": "Update", "clean": "Clean_Install", "personal": "Configured"}[kind]
    dest = output / ("GameHUB_3_Liquid_Glass_" + data["Version"] + "_" + suffix + ".zip")
    manifest = {"release": data, "kind": kind, "files": {}}
    payload["READ_ME_FIRST.txt"] = readme.encode("utf-8")
    for name, content in sorted(payload.items()):
        manifest["files"][name] = hashlib.sha256(content).hexdigest()
    payload["RELEASE_MANIFEST.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
    date = datetime.strptime(data["Build"].split(".")[0], "%Y%m%d")
    stamp = (date.year, date.month, date.day, 0, 0, 0)
    temporary = dest.with_suffix(".zip.tmp")
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for name, content in sorted(payload.items()):
                info = zipfile.ZipInfo(name, date_time=stamp)
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, content, compresslevel=6)
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError("ZIP CRC validation failed")
        temporary.replace(dest)
    finally:
        if temporary.exists():
            temporary.unlink()
    print(dest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--stamp", action="store_true")
    action.add_argument("--check", action="store_true")
    action.add_argument("--package", choices=("update", "clean", "personal", "full"), help="full aliases clean")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    data = release()
    if args.stamp:
        for path, expected in expected_texts(data):
            if path.read_bytes() != expected:
                path.write_bytes(expected)
    if args.package:
        if args.output is None:
            parser.error("--package requires --output outside the skin folder")
        output = args.output.resolve()
        if output == ROOT or ROOT in output.parents:
            parser.error("Package output must be outside the skin folder")
        package(args.package, output, data)
    else:
        check(data)
        print("Release metadata consistent: {Version} / {Build}".format(**data))


if __name__ == "__main__":
    main()
