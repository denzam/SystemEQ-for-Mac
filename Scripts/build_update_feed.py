#!/usr/bin/env python3
import argparse
import base64
import html
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
FEED_URL = 'https://github.com/denzam/SystemEQ-for-Mac/releases/latest/download/appcast.xml'

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def generate(app, archive, tools, output, version, notes):
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Invalid release version')
    require(not output.exists() and not output.is_symlink(), 'Feed output already exists')
    require(output.parent.is_dir() and not output.parent.is_symlink(), 'Invalid feed output directory')
    require(archive.is_file() and not archive.is_symlink() and archive.name == f'SystemEQ-v{version}.zip', 'Invalid update archive')
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    require(info['CFBundleShortVersionString'] == version and re.fullmatch(r'[1-9][0-9]*', str(info['CFBundleVersion'])), 'Invalid update version or build')
    require(info.get('SUFeedURL') == FEED_URL and info.get('SURequireSignedFeed') is True and info.get('SUVerifyUpdateBeforeExtraction') is True, 'Missing signed update configuration')
    with (ROOT / 'Config/Info.plist').open('rb') as stream:
        trusted = plistlib.load(stream)
    require(info.get('SUPublicEDKey') == trusted.get('SUPublicEDKey'), 'Unexpected update public key')
    key = os.environ.get('SPARKLE_ED25519_PRIVATE_KEY', '')
    require(key and len(base64.b64decode(key, validate=True)) == 32, 'Missing or invalid private update key')
    generator = tools / 'bin/generate_appcast'
    require(generator.is_file() and os.access(generator, os.X_OK), 'Missing appcast generator')
    attempt = Path(tempfile.mkdtemp(prefix='systemeq-appcast-', dir=output.parent)).resolve()
    staged = attempt / archive.name
    shutil.copyfile(archive, staged)
    (attempt / f'{archive.stem}.html').write_text('<html><body><pre style="white-space:pre-wrap">' + html.escape(notes.read_text()) + '</pre></body></html>')
    url_prefix = f'https://github.com/denzam/SystemEQ-for-Mac/releases/download/v{version}/'
    command = [str(generator.resolve()), '--ed-key-file', '-', '--download-url-prefix', url_prefix,
               '--maximum-deltas', '0', '--maximum-versions', '1', '--versions', str(info['CFBundleVersion']),
               '--embed-release-notes', '-o', str(attempt / 'appcast.xml'), str(attempt)]
    environment = {name: value for name, value in os.environ.items() if name != 'SPARKLE_ED25519_PRIVATE_KEY'}
    try:
        result = subprocess.run(command, input=(key + '\n').encode(), capture_output=True, cwd=attempt, timeout=300, env=environment)
    except subprocess.TimeoutExpired as error:
        diagnostic = ((error.stdout or b'') + (error.stderr or b'')).decode(errors='replace').replace(key, '<redacted>')
        (attempt / 'generation.log').write_text(diagnostic)
        raise RuntimeError('Appcast generation timed out; sanitized diagnostics preserved') from None
    (attempt / 'generation.log').write_text((result.stdout + result.stderr).decode(errors='replace').replace(key, '<redacted>'))
    require(result.returncode == 0, 'Appcast generation failed; sanitized diagnostics preserved')
    require(staged.read_bytes() == archive.read_bytes(), 'Archive changed while generating feed')
    checked = subprocess.run(['swift', str(ROOT / 'Scripts/verify_update_feed.swift'), str(attempt / 'appcast.xml'), str(staged),
                              info['SUPublicEDKey'], url_prefix + archive.name, str(info['CFBundleVersion']), version],
                             capture_output=True, timeout=90, env=environment)
    (attempt / 'verification.log').write_bytes(checked.stdout + checked.stderr)
    require(checked.returncode == 0, 'Signed appcast validation failed')
    with output.open('xb') as stream:
        stream.write((attempt / 'appcast.xml').read_bytes())
    print('Signed update feed and archive verified; feed written')

def main():
    parser = argparse.ArgumentParser()
    for name in ('app', 'archive', 'tools', 'output', 'notes'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    generate(args.app, args.archive, args.tools, args.output, args.version, args.notes)

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'Update feed preparation failed: {type(error).__name__}', file=sys.stderr)
        sys.exit(1)
