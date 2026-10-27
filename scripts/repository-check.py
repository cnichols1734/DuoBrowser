#!/usr/bin/env python3
"""Repository hygiene checks. This is not a substitute for a secret scanner."""
import json
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
errors = []
for name in filter(None, paths):
    p = root / name
    if not p.is_file():
        continue
    if p.stat().st_size > 5 * 1024 * 1024:
        errors.append(f'Large tracked file: {name}')
    if re.search(r'(?i)(\.(p12|p8|pem|cer|key|mobileprovision|provisionprofile|ipa|xcarchive|xcresult)$|(^|/)\.env($|\.))', name):
        errors.append(f'Sensitive/build filename: {name}')
    if any(part in {'work', 'DerivedData', 'node_modules', 'xcuserdata'} for part in p.relative_to(root).parts):
        errors.append(f'Tracked local artifact: {name}')

project = (root / 'DuoBrowser.xcodeproj/project.pbxproj').read_text()
if re.search(r'"?DEVELOPMENT_TEAM"?\s*=\s*"?\w+', project):
    errors.append('Tracked development team')
if 'PBXShellScriptBuildPhase' in project or 'XCRemoteSwiftPackageReference' in project:
    errors.append('New build script/package requires security and license policy review')

manifest = json.loads((root / 'package.json').read_text())
lock = json.loads((root / 'package-lock.json').read_text())
if not manifest.get('private') or manifest.get('dependencies'):
    errors.append('Tool package must be private and development-only')
if lock.get('lockfileVersion') != 3:
    errors.append('Expected npm lockfile v3')
allowed = {'playwright', 'playwright-core', 'fsevents'}
for location, package in lock['packages'].items():
    if not location:
        continue
    name = location.removeprefix('node_modules/')
    if name not in allowed:
        errors.append(f'Unreviewed dependency: {name}')
    if package.get('license') not in {'Apache-2.0', 'MIT'}:
        errors.append(f'Unreviewed dependency license: {name}')
    if not package.get('resolved', '').startswith('https://registry.npmjs.org/') or not package.get('integrity', '').startswith('sha512-'):
        errors.append(f'Missing trusted registry/integrity: {name}')
    if package.get('hasInstallScript'):
        errors.append(f'Dependency lifecycle script requires review: {name}')
if lock['packages'][''].get('devDependencies') != manifest.get('devDependencies'):
    errors.append('Manifest/lockfile mismatch')

for workflow in (root / '.github/workflows').glob('*.yml'):
    text = workflow.read_text()
    if any(word in text for word in ['pull_request_target', 'self-hosted', 'secrets.', 'write-all']):
        errors.append(f'Unsafe community workflow policy: {workflow.name}')
    for action in re.findall(r'uses:\s*(\S+)', text):
        if not re.fullmatch(r'[\w.-]+/[\w./-]+@[0-9a-f]{40}', action):
            errors.append(f'Action must use a full commit SHA: {workflow.name}')
    if 'persist-credentials: false' not in text:
        errors.append(f'Checkout credentials must not persist: {workflow.name}')

if errors:
    raise SystemExit('\n'.join(errors))
print('Repository, dependency-license, lockfile and workflow-policy checks passed')
