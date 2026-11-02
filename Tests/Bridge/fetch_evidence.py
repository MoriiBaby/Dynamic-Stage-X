#!/usr/bin/env python3
"""Replay pinned public-header evidence; only HTTPS GET, no API tree/rate-limit dependency."""
import concurrent.futures,hashlib,json,pathlib,urllib.request
ROOT=pathlib.Path(__file__).resolve().parent
ALLOWED={'MTACS/iOS-17-Runtime-Headers','nst/iOS-Runtime-Headers','theos/headers'}
def main():
    manifest=json.loads((ROOT/'evidence-manifest.json').read_text())
    def fetch(item):
        assert item['repository'] in ALLOWED
        expected=f"https://raw.githubusercontent.com/{item['repository']}/{item['revision']}/{item['path']}"
        assert item['url']==expected and len(item['revision'])==40
        dst=ROOT/item['local']
        assert dst.resolve().is_relative_to((ROOT/'evidence').resolve())
        if dst.exists():
            assert hashlib.sha256(dst.read_bytes()).hexdigest()==item['sha256'],str(dst)
            return
        request=urllib.request.Request(expected,headers={'User-Agent':'DynamicStageX-public-header-research'})
        with urllib.request.urlopen(request,timeout=30) as response: data=response.read()
        assert len(data)==item['bytes'] and hashlib.sha256(data).hexdigest()==item['sha256'],expected
        dst.parent.mkdir(parents=True,exist_ok=True)
        # Do not overwrite original evidence, even if another fetch ran in parallel.
        with dst.open('xb') as output: output.write(data)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: list(pool.map(fetch,manifest))
    print(f'Verified/preserved {len(manifest)} fixed-revision public headers; no device or remote write operations.')
if __name__=='__main__': main()
