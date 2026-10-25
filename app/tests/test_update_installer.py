"""Exercise the production installer in disposable folders, with OS launch mocked."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

INSTALLER = Path(__file__).resolve().parents[1] / "data/install-update.sh"


class InstallerTests(unittest.TestCase):
    def run_installer(self, fail_move=False, fail_open=False, parent_alive=False):
        with tempfile.TemporaryDirectory(prefix="anmir installer ' ") as folder:
            root = Path(folder)
            target = root / "Anmir ' space.app"
            target.mkdir()
            (target / "version").write_text("old")
            stage = root / ".stage"
            stage.mkdir()
            (stage / "Anmir.app").mkdir()
            (stage / "Anmir.app/version").write_text("new")
            work = root / "work"
            work.mkdir()
            mock_open = root / "open"
            mock_open.write_text('#!/bin/sh\n[ "${FAIL_OPEN:-}" != 1 ]\n')
            mock_open.chmod(0o700)
            mock_mv = root / "mv"
            mock_mv.write_text('''#!/bin/sh
if [ "${FAIL_MOVE:-}" = 1 ] && [ "$1" = "$TEST_STAGE/Anmir.app" ]; then exit 1; fi
exec /bin/mv "$@"
''')
            mock_mv.chmod(0o700)
            # Only OS entry points are substituted; use the real install logic.
            source = INSTALLER.read_text().replace('/usr/bin/open', '"$TEST_OPEN"').replace('/bin/mv', '"$TEST_MV"')
            script = root / "installer.sh"
            if parent_alive:
                source = source.replace('/bin/sleep 1', ':')
            script.write_text(source)
            env = dict(os.environ, TEST_OPEN=str(mock_open), TEST_MV=str(mock_mv), TEST_STAGE=str(stage),
                       FAIL_MOVE=str(int(fail_move)), FAIL_OPEN=str(int(fail_open)))
            result = subprocess.run(["/bin/sh", str(script), str(os.getpid()) if parent_alive else "2147483647", str(stage), str(target), str(work)], env=env, timeout=10)
            self.assertEqual(result.returncode, 1 if fail_move or fail_open or parent_alive else 0)
            self.assertEqual((target / "version").read_text(), "old" if fail_move or fail_open or parent_alive else "new")
            self.assertFalse(stage.exists())
            self.assertFalse(work.exists())
            backups = list(root.glob("*.previous-*.app"))
            if not fail_move and not fail_open and not parent_alive:
                self.assertEqual(len(backups), 1)
                self.assertEqual((backups[0] / "version").read_text(), "old")

    def test_install_retains_backup(self):
        self.run_installer()

    def test_failed_replacement_restores_old_app(self):
        self.run_installer(fail_move=True)

    def test_cancelled_quit_leaves_running_installation_untouched(self):
        self.run_installer(parent_alive=True)

    def test_failed_launch_restores_old_app(self):
        self.run_installer(fail_open=True)


if __name__ == "__main__":
    unittest.main()
