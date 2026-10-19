"""Build a clean installation ZIP from source; no live device files."""
from pathlib import Path
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'src/mydash_v2/VERSION').read_text().strip()
OUTPUT = ROOT / 'dist' / f'kindle-dashboard-{VERSION}.zip'


def build():
    OUTPUT.parent.mkdir(exist_ok=True)
    prefix = f'kindle-dashboard-{VERSION}/'
    with zipfile.ZipFile(OUTPUT, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((ROOT / 'src').rglob('*')):
            if not path.is_file() or 'cache' in path.relative_to(ROOT / 'src').parts:
                continue
            # Only code and explicit defaults enter the install package.
            if path.suffix not in {'.lua', '.sh', '.map'} and path.name not in {
                'VERSION', 'DISABLE_AUTOSTART', 'config.example.json', 'markets_config.example.json'
            }:
                continue
            relative = path.relative_to(ROOT / 'src').as_posix().replace('.example.json', '.json')
            data = path.read_bytes()
            if relative.endswith('.json'):
                json.loads(data)
            archive.write(path, prefix + relative)
        archive.writestr(prefix + 'mydash_v2/cache/', '')
        for name in ['README.md', 'INSTALL.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CHANGELOG.md']:
            archive.write(ROOT / name, prefix + name)
        for path in (ROOT / 'docs/images').glob('*.png'):
            archive.write(path, prefix + path.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(OUTPUT) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert prefix + 'mydash_v2/home.lua' in names
        assert prefix + 'mydash_v2/config.json' in names
        assert not any(name.endswith(('.epub', '.mobi', '.pdf', '.log')) for name in names)
        assert not any('/backups/' in name or 'history.lua' in name for name in names)
    print(OUTPUT)


if __name__ == '__main__':
    build()
