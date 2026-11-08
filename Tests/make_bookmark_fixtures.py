"""Synthetic Safari archives; credentials are deliberately invalid compressed bytes to prove they are ignored."""
from pathlib import Path
from zipfile import ZipFile, ZIP_STORED, ZIP_DEFLATED
root = Path('work/checks'); root.mkdir(parents=True, exist_ok=True)
html = Path('Tests/Fixtures/SafariImport/Bookmarks.html').read_bytes()
for name, method, filename in [('stored', ZIP_STORED, 'Bookmarks.html'), ('deflated', ZIP_DEFLATED, 'Bookmarks.html'), ('localized', ZIP_DEFLATED, 'Lesezeichen.html')]:
    with ZipFile(root / (name + '.zip'), 'w', compression=method) as archive:
        archive.writestr(filename, html)
        archive.writestr('Passwords.csv', b'synthetic-not-imported')
        archive.writestr('History.json', b'synthetic-not-imported')
