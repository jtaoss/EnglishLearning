"""Read-only live Notion snapshot using existing WinCred; no credential output/files.

Only GET data source and POST data source/query are implemented. There is no write API.
"""
import ctypes as C
from ctypes import wintypes as W
import datetime
import hashlib
import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'private/p5a'
OUT.mkdir(parents=True, exist_ok=True)


class Credential(C.Structure):
    _fields_ = [('Flags', W.DWORD), ('Type', W.DWORD), ('TargetName', W.LPWSTR),
                ('Comment', W.LPWSTR), ('LastWritten', W.FILETIME),
                ('CredentialBlobSize', W.DWORD), ('CredentialBlob', C.POINTER(C.c_ubyte)),
                ('Persist', W.DWORD), ('AttributeCount', W.DWORD), ('Attributes', C.c_void_p),
                ('TargetAlias', W.LPWSTR), ('UserName', W.LPWSTR)]


def run():
    api = C.WinDLL('Advapi32.dll', use_last_error=True)
    ptr = C.POINTER(Credential)()
    api.CredReadW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, C.POINTER(C.POINTER(Credential))]
    api.CredReadW.restype = W.BOOL
    api.CredFree.argtypes = [C.c_void_p]
    if not api.CredReadW('EnglishLearning.Notion.ReadOnly.v1', 1, 0, C.byref(ptr)):
        raise RuntimeError('Existing read-only Windows credential unavailable')
    try:
        blob = C.string_at(ptr.contents.CredentialBlob, ptr.contents.CredentialBlobSize)
        account = json.loads(blob.decode('utf-8'))
    finally:
        C.memset(ptr.contents.CredentialBlob, 0, ptr.contents.CredentialBlobSize)
        api.CredFree(ptr)
    token = account['token']
    ds = account['data_source_id']
    assert ds.replace('-', '') == '157d89e571fb4e6896401b04dbb1e627'
    calls = []

    def request(suffix, body=None):
        # Fixed endpoints: query POST is read-only; no page/schema/event writes.
        method = 'GET' if body is None else 'POST'
        assert suffix == '' or suffix == '/query'
        path = f'/v1/data_sources/{ds}{suffix}'
        req = urllib.request.Request('https://api.notion.com' + path,
              data=None if body is None else json.dumps(body).encode(),
              headers={'Authorization': 'Bearer ' + token, 'Notion-Version': '2025-09-03',
                       'Content-Type': 'application/json'}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                result = json.load(r)
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'Notion read failed with HTTP {e.code}') from None
        calls.append({'method': method, 'path': path, 'read_only': True})
        return result

    schema = request('')
    rows = []
    cursor = None
    while True:
        query = {'page_size': 100}
        if cursor:
            query['start_cursor'] = cursor
        result = request('/query', query)
        rows.extend(result['results'])
        if not result['has_more']:
            break
        cursor = result['next_cursor']
        assert cursor
    assert len(rows) == 500
    snapshot = {'fetched_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'schema': schema, 'results': rows, 'has_more': False, 'calls': calls,
                'credential_storage': 'existing Windows Credential Manager; memory only',
                'content_writes': 0, 'event_uploads': 0}
    data = json.dumps(snapshot, ensure_ascii=False, indent=2).encode()
    (OUT / 'notion-direct-live.json').write_bytes(data)
    print(json.dumps({'rows': len(rows), 'properties': len(schema['properties']),
                      'read_requests': len(calls), 'snapshot_sha256': hashlib.sha256(data).hexdigest(),
                      'writes': 0}))


if __name__ == '__main__':
    try:
        run()
    except Exception as exc:
        # Error type only: never echo credential blobs, headers or request bodies.
        print('Read-only snapshot failed: ' + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
