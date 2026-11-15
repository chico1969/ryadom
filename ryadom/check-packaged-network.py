"""Inspect the packaged C ABI without opening a session or revealing credentials."""
import ctypes
import json
import os
from pathlib import Path

root = Path(__file__).resolve().parents[1]
bundle = root / 'flutter/build/windows/x64/runner/Release'
with os.add_dll_directory(str(bundle)):
    library = ctypes.CDLL(str(bundle / 'librustdesk.dll'))
    request = library.ryadom_request_v1
    request.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32]
    request.restype = ctypes.c_int32
    raw = b'{"action":"network-get"}'
    source = ctypes.create_string_buffer(raw)
    output = ctypes.create_string_buffer(65536)
    length = request(source, len(raw), output, len(output))
    if length <= 0:
        raise RuntimeError('Packaged network configuration cannot be read')
    state = json.loads(output.raw[:length])
    if state.get('error') or not state.get('sharedTestBuild') or not state.get('configured'):
        raise RuntimeError('Family TURN configuration is not enabled')
    if not state.get('urls') or not all(url.startswith('turn:free.expressturn.com:3478') for url in state['urls']):
        raise RuntimeError('Unexpected TURN provider in family package')
    result = {'status': 'passed', 'bundledFamilyTurn': True, 'configured': True,
              'provider': 'ExpressTURN', 'scope': 'Packaged DLL C ABI; shared credentials recoverable from executable; no remote session'}
    (root / 'ryadom/build-logs/packaged-network.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
