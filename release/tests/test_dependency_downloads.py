import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


INIT = Path(__file__).resolve().parents[2] / 'app/deps/_init'


class DownloadTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.payload = b'verified archive contents\n'
        self.archive = self.root / 'original'
        self.archive.write_bytes(self.payload)
        self.output = self.root / 'download.tar.xz'
        self.calls = self.root / 'calls'
        for name in ('wget', 'curl'):
            client = self.bin / name
            client.write_text('''#!/bin/sh
name=${0##*/}
echo "$name $*" >> "$ANMIR_TEST_CALLS"
while [ "$#" -gt 0 ]; do
    case "$1" in -O|--output) output=$2; shift;; esac
    shift
done
if [ "$name" = wget ] && [ "${ANMIR_TEST_WGET_FAIL:-}" = 1 ]; then
    echo partial > "$output"; exit 4
fi
if [ "$name" = curl ] && [ "${ANMIR_TEST_CURL_FAIL:-}" = 1 ]; then
    echo partial > "$output"; exit 22
fi
if [ "${ANMIR_TEST_BAD_PAYLOAD:-}" = 1 ]; then
    echo corrupted > "$output"
else
    cat "$ANMIR_TEST_ARCHIVE" > "$output"
fi
''')
            client.chmod(0o755)

    def download(self, **overrides):
        environment = os.environ.copy()
        environment.update(PATH=str(self.bin) + os.pathsep + environment['PATH'],
            ANMIR_TEST_CALLS=str(self.calls), ANMIR_TEST_ARCHIVE=str(self.archive), **overrides)
        result = subprocess.run(['bash', '-c',
            'set -e; source "$1"; cd "$2"; get_file "$3" "$4" "$5"',
            'download-test', str(INIT), str(self.root), 'https://example.invalid/archive',
            str(self.output), hashlib.sha256(self.payload).hexdigest()],
            env=environment, capture_output=True, text=True)
        self.assertEqual(list(self.root.glob('download.tar.xz.*')), [], result.stdout + result.stderr)
        return result

    def test_valid_cache_needs_no_network(self):
        self.output.write_bytes(self.payload)
        self.assertEqual(self.download().returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_wget_failure_falls_back_to_verified_curl_download(self):
        result = self.download(ANMIR_TEST_WGET_FAIL='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.output.read_bytes(), self.payload)
        calls = self.calls.read_text()
        self.assertIn('curl --fail --location --retry 3', calls)
        self.assertNotIn('--insecure', calls)

    def test_corrupt_cache_is_downloaded_again(self):
        self.output.write_bytes(b'incomplete')
        self.assertEqual(self.download().returncode, 0)
        self.assertEqual(self.output.read_bytes(), self.payload)

    def test_failed_clients_leave_no_cache_entry(self):
        self.assertNotEqual(self.download(ANMIR_TEST_WGET_FAIL='1', ANMIR_TEST_CURL_FAIL='1').returncode, 0)
        self.assertFalse(self.output.exists())

    def test_checksum_mismatch_is_not_cached(self):
        self.assertNotEqual(self.download(ANMIR_TEST_BAD_PAYLOAD='1').returncode, 0)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
