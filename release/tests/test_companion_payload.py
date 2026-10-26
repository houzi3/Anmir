import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('verify_companion', Path(__file__).resolve().parents[1] / 'verify_companion.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class PayloadTest(unittest.TestCase):
    def test_signatures_are_allowed_but_payload_changes_are_not(self):
        with tempfile.TemporaryDirectory() as work:
            unsigned = Path(work) / 'unsigned.apk'
            signed = Path(work) / 'signed.apk'
            def write(path, code, extra=None):
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr('AndroidManifest.xml', b'manifest')
                    archive.writestr('classes.dex', code)
                    if extra: archive.writestr(*extra)
            write(unsigned, b'code')
            write(signed, b'code', ('META-INF/CERT.RSA', b'signature'))
            module.verify_payload(unsigned, signed)
            write(signed, b'changed')
            with self.assertRaises(ValueError): module.verify_payload(unsigned, signed)
            write(signed, b'code', ('assets/unexpected', b'extra'))
            with self.assertRaises(ValueError): module.verify_payload(unsigned, signed)

if __name__ == '__main__': unittest.main()
