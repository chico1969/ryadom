"""Reject a package whose runtime name cannot be installed as the Ryadom service."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
bundle = root / 'flutter/build/windows/x64/runner/Release'
payload = (root / 'libs/portable/data.bin').read_bytes()
entry = payload.rsplit(b'rustdesk', 1)[-1].decode('utf-8').replace('\\', '/').removeprefix('./')
if entry != 'Ryadom.exe' or not (bundle / entry).is_file() or (bundle / 'rustdesk.exe').exists():
    raise RuntimeError('The packaged runtime must be Ryadom.exe, matching the service and shortcuts')
result = {'status': 'passed', 'runtime': entry, 'scope': 'Portable entry point and installed executable name match; not a service start test'}
(root / 'ryadom/build-logs/windows-package-name.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result))
