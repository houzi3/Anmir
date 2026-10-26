#!/usr/bin/env python3
"""Sign a CI-built APK locally; private signing material never leaves this host."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from verify_companion import build_tool, verify_certificate, verify_payload

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('unsigned', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--properties', type=Path, default=Path.home() / 'important_key/android_keystore/signing.properties')
args = parser.parse_args()
if args.unsigned.resolve() == args.output.resolve():
    raise SystemExit('Keep the original unsigned CI artifact unchanged.')
if args.output.exists():
    verify_payload(args.unsigned, args.output)
    verify_certificate(args.output)
    print('Existing signed APK verified:', args.output)
    raise SystemExit(0)
values = {}
for line in args.properties.read_text().splitlines():
    if not line.strip() or line.lstrip().startswith(('#', '!')):
        continue
    key, separator, value = line.partition('=')
    if not separator or '\\' in value:
        raise SystemExit('Use plain key=value signing properties without Java escape sequences.')
    values[key.strip()] = value.strip()
for name in ('storeFile', 'storePassword', 'keyAlias', 'keyPassword'):
    if not values.get(name):
        raise SystemExit('Missing signing property: ' + name)
keystore = Path(values['storeFile'])
if not keystore.is_absolute():
    keystore = args.properties.parent / keystore
environment = os.environ.copy()
environment['ANMIR_SIGN_STORE_PASSWORD'] = values['storePassword']
environment['ANMIR_SIGN_KEY_PASSWORD'] = values['keyPassword']
args.output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='anmir-sign-') as work:
    aligned = Path(work) / 'aligned.apk'
    signed = Path(work) / 'signed.apk'
    subprocess.run([str(build_tool('zipalign')), '-f', '4', str(args.unsigned), str(aligned)], check=True)
    subprocess.run([str(build_tool('apksigner')), 'sign', '--ks', str(keystore),
                    '--ks-type', values.get('storeType', 'PKCS12'), '--ks-key-alias', values['keyAlias'], '--ks-pass', 'env:ANMIR_SIGN_STORE_PASSWORD',
                    '--key-pass', 'env:ANMIR_SIGN_KEY_PASSWORD', '--out', str(signed), str(aligned)],
                   env=environment, check=True)
    verify_payload(args.unsigned, signed)
    verify_certificate(signed)
    args.output.write_bytes(signed.read_bytes())
print('Signed and verified:', args.output)
