#!/usr/bin/env python3
"""Check that local signing changed no APK payload and used the pinned certificate."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def verify_payload(unsigned, signed):
    signature = re.compile(r'META-INF/(?:[^/]+\.(?:SF|RSA|DSA|EC)|MANIFEST\.MF)$', re.I)
    with zipfile.ZipFile(unsigned) as before, zipfile.ZipFile(signed) as after:
        old = {v.filename for v in before.infolist() if not signature.fullmatch(v.filename)}
        new = {v.filename for v in after.infolist() if not signature.fullmatch(v.filename)}
        if old != new:
            raise ValueError('Signed APK contains a different file set')
        for name in old:
            if hashlib.sha256(before.read(name)).digest() != hashlib.sha256(after.read(name)).digest():
                raise ValueError('Signed APK payload differs: ' + name)


def build_tool(name):
    sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
    return sdk / 'build-tools/36.0.0' / name


def verify_certificate(apk):
    output = subprocess.check_output([str(build_tool('apksigner')), 'verify', '--print-certs', str(apk)], text=True)
    digests = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-f]+)$', output, re.M)
    expected = (Path(__file__).resolve().parents[1] / 'companion/release-certificate.sha256').read_text().strip()
    if digests != [expected]:
        raise ValueError('Unexpected Android signing certificate')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: verify_companion.py UNSIGNED_APK SIGNED_APK')
    verify_payload(sys.argv[1], sys.argv[2])
    verify_certificate(sys.argv[2])
    print('APK payload and release certificate verified.')
