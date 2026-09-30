#!/usr/bin/env python3
"""Test release isolation/reproducibility with disposable data; no installed data writes."""
import configparser
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gamehub_release', ROOT / 'Maintenance/release.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
data = mod.release()
mod.check(data)

def read_ini(raw):
    p = configparser.RawConfigParser(interpolation=None)
    p.optionxform = str
    p.read_string(raw.decode('utf-8-sig'))
    return p

with tempfile.TemporaryDirectory(prefix='gamehub-release-test-') as directory:
    root = Path(directory) / 'GameHUBGlass'
    for name in mod.SHARED_FILES:
        p = root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, p)
    personal = {
        '@Resources/Library.ini': b'[Library]\nVersion=3\n[Game:secret]\nName=Private game\nTarget=C:\\Private\\Game.exe\n',
        '@Resources/State.ini': b'[State]\nView=list\n[Favorites]\nsecret=1\n[History]\nsecret=1790000000\n[LaunchCounts]\nsecret=12\n',
        '@Resources/Settings.ini': b'[Settings]\nUIScale=1.4\nPrivateSetting=Keep\n',
        '@Resources/Art/Previews/private.mp4': b'personal-video-sentinel',
        '@Resources/Art/Logos/private.png': b'personal-logo-sentinel',
        '@Resources/Art/Originals/private.jpg': b'personal-art-sentinel',
        '@Resources/Shortcuts/private.lnk': b'personal-shortcut-sentinel',
    }
    excluded = {
        '@Resources/Motion-status.ini': b'[Motion]\nPhase=error\nLastError=old error\n',
        '@Resources/Motion.log': b'old compiler error',
        '@Resources/Motion-command.ini': b'[Motion]\nAction=play\nVideo=C:\\Private\\clip.mp4\n',
        '@Resources/Motion-command.ini.tmp': b'old media command',
        '@Resources/Manager.log': b'stale error',
        '@Resources/Manager-status.ini': b'[Manager]\nStatus=error\n',
        '@Resources/Manager-diagnostics.txt': b'old error',
        '@Resources/Library.ini.bak': b'old private library',
        '@Resources/Settings.ini.new': b'private temporary settings',
        '@Resources/Art/Originals/private.jpg.bak': b'old art',
        '@Resources/Art/Originals/.secret': b'hidden',
        'unreviewed-private-note.txt': b'secret-note-sentinel',
        'UPDATE_0.1.1.txt': b'historical installation notes',
    }
    for name, raw in {**personal, **excluded}.items():
        p = root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(raw)
    before = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
    for kind, suffix in [('update', 'Update'), ('clean', 'Clean_Install'), ('personal', 'Configured')]:
        outputs = []
        for run in (1, 2):
            out = Path(directory) / f'{kind}-{run}'
            subprocess.run([sys.executable, str(root / 'Maintenance/release.py'), '--package', kind,
                            '--output', str(out)], check=True, stdout=subprocess.PIPE, text=True)
            p = out / ('GameHUB_3_Liquid_Glass_' + data['Version'] + '_' + suffix + '.zip')
            outputs.append(p.read_bytes())
        assert outputs[0] == outputs[1], kind + ' package is not reproducible'
        with zipfile.ZipFile(p) as z:
            assert z.testzip() is None
            names = set(z.namelist())
            manifest = json.loads(z.read('RELEASE_MANIFEST.json'))
            assert manifest['release'] == data and manifest['kind'] == kind
            assert names == set(manifest['files']) | {'RELEASE_MANIFEST.json'}
            for name, expected in manifest['files'].items():
                assert hashlib.sha256(z.read(name)).hexdigest() == expected, name
            for name in excluded:
                assert 'GameHUBGlass/' + name not in names, name
            if kind == 'update':
                assert not any(mod.protected(Path(n).relative_to('GameHUBGlass'))
                               for n in names if n.startswith('GameHUBGlass/'))
            elif kind == 'clean':
                lib = read_ini(z.read('GameHUBGlass/@Resources/Library.ini'))
                state = read_ini(z.read('GameHUBGlass/@Resources/State.ini'))
                settings = read_ini(z.read('GameHUBGlass/@Resources/Settings.ini'))
                assert lib.sections() == ['Library'] and lib['Library']['Version'] == data['LibrarySchema']
                assert state['State']['View'] == 'home' and 'ButtonPositioned' not in state['State']
                assert not any(state[s] for s in ['Favorites', 'History', 'LaunchCounts'])
                assert settings['Settings']['UIScale'] == '1' and 'PrivateSetting' not in settings['Settings']
                assert not any('/Art/' in n or '/Shortcuts/' in n for n in names)
            else:
                for name, raw in personal.items():
                    assert z.read('GameHUBGlass/' + name) == raw, name
            if kind != 'personal':
                assert not any(b'sentinel' in z.read(n) for n in names if not n.endswith('Test-Release.py'))
        print(kind + ': isolation, data preservation, manifest/CRC and reproducibility PASS')
    after = {str(p.relative_to(root)): p.read_bytes() for p in root.rglob('*') if p.is_file()}
    assert after == before, 'Packaging changed source data'
print('Release packaging passed; source data untouched.')
