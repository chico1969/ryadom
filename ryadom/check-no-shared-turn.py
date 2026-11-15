"""Check distribution inputs against the owner's local TURN test credentials."""
import argparse
import json
from pathlib import Path
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--windows', action='store_true')
parser.add_argument('--web', action='store_true')
parser.add_argument('--sources', action='store_true')
args = parser.parse_args()
private = list((root / '.tools').glob('turn*.local.json'))
if not private:
    sys.exit('No local reference credentials; owner-specific scan cannot run.')
servers = [server for file in private for server in json.loads(file.read_text(encoding='utf-8-sig'))]
values = {server[key] for server in servers for key in ('username', 'credential') if server.get(key)}
if not values:
    sys.exit('No local reference credentials; scan would be empty.')
needles = [value.encode(encoding) for value in values for encoding in ('utf-8', 'utf-16-le')]
bad = []
checked = 0

def check(name, data):
    global checked
    checked += 1
    if any(needle in data for needle in needles):
        bad.append(name)

for enabled, folder in (
    (args.windows, root / 'flutter/build/windows/x64/runner/Release'),
    (args.web, root / 'ryadom/ui/build/web'),
):
    if enabled:
        if not folder.is_dir():
            sys.exit('Distribution input is missing.')
        for file in folder.rglob('*'):
            if file.is_file() and 'source' not in file.relative_to(folder).parts:
                check(str(file.relative_to(root)), file.read_bytes())

if args.sources:
    archive = root / 'dist/development/Ryadom-Sources-development.zip'
    with zipfile.ZipFile(archive) as source:
        for item in source.infolist():
            if item.is_dir():
                continue
            if any(part in ('.tools', '.git', 'node_modules') for part in Path(item.filename).parts):
                bad.append(item.filename)
            check(item.filename, source.read(item))

result = {'status': 'failed' if bad else 'passed', 'checkedFiles': checked,
          'scope': 'Known owner TURN username/password absent in UTF-8 and UTF-16; not a full security audit',
          'matchedFiles': bad}
print(json.dumps(result, ensure_ascii=False, indent=2))
sys.exit(bool(bad))
