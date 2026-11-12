#!/usr/bin/env python3
"""Refresh separately licensed source data, then run native compilation checks before committing."""
import datetime
import hashlib
import json
import pathlib
import urllib.request

root = pathlib.Path(__file__).resolve().parents[1] / 'DuoBrowser' / 'FilterLists'
sources = {
    'easylist': 'https://easylist.to/easylist/easylist.txt',
    'easyprivacy': 'https://easylist.to/easylist/easyprivacy.txt',
    'cookies': 'https://secure.fanboy.co.nz/fanboy-cookiemonster.txt',
}
received = {}
for name, url in sources.items():
    request = urllib.request.Request(url, headers={'User-Agent': 'DuoBrowser-Filter-Maintenance/1.0'})
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.url != url:
            raise SystemExit('Unexpected filter redirect')
        data = response.read(5_000_001)
    if len(data) > 5_000_000 or not data.startswith(b'[Adblock Plus'):
        raise SystemExit('Invalid or oversized filter list: ' + name)
    data.decode('utf-8')
    received[name] = data
receipt = {
    'date': (datetime.datetime.now(datetime.timezone.utc) - datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)).total_seconds(),
    'sources': {name: hashlib.sha256(data).hexdigest() for name, data in received.items()},
    'urls': sources,
}
receipt['upstreamSHA256'] = dict(receipt['sources'])
receipt['transformation'] = 'Trailing whitespace removed from comment lines only; filter rules unchanged.'
for name, data in received.items():
    normalized = ('\n'.join(line.rstrip() if line.startswith('!') else line for line in data.decode('utf-8').splitlines()) + '\n').encode('utf-8')
    (root / (name + '.txt')).write_bytes(normalized)
    receipt['sources'][name] = hashlib.sha256(normalized).hexdigest()
(root / 'metadata.json').write_text(json.dumps(receipt, indent=2) + '\n')
print('Updated three source lists. Review upstream licensing, run checks and native WebKit compilation, then submit a PR.')
