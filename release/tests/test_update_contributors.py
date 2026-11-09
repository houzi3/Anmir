import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'update_contributors.py'
SPEC = importlib.util.spec_from_file_location('update_contributors', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def commit(login=None, account_type='User'):
    author = None if login is None else {'login': login, 'type': account_type}
    return {'author': author}


class FakeAPI:
    def __init__(self, pages):
        self.pages = list(pages)
        self.calls = []

    def get(self, path, **parameters):
        self.calls.append((path, parameters))
        if path == '/repos/houzi3/Anmir':
            return {
                'default_branch': 'main',
                'parent': {'full_name': 'Genymobile/scrcpy'},
                'source': {'full_name': 'Genymobile/scrcpy'},
            }
        if path == '/repos/Genymobile/scrcpy':
            return {'default_branch': 'master'}
        return self.pages.pop(0)


class ContributorTest(unittest.TestCase):
    def test_two_contributors_keep_existing_rendering(self):
        self.assertEqual(MODULE.render_contributors(['houzi3', 'ztygalaxy']),
            '[<img src="https://github.com/houzi3.png?size=120" width="60" height="60" alt="@houzi3">](https://github.com/houzi3)&nbsp;\n'
            '[<img src="https://github.com/ztygalaxy.png?size=120" width="60" height="60" alt="@ztygalaxy">](https://github.com/ztygalaxy)')

    def test_ninth_contributor_starts_a_new_row(self):
        rendered = MODULE.render_contributors([f'user{number}' for number in range(9)])
        lines = rendered.splitlines()
        self.assertEqual(lines[8], '<br>')
        self.assertIn('@user7', lines[7])
        self.assertNotIn('&nbsp;', lines[7])
        self.assertIn('@user8', lines[9])

    def test_compare_is_paginated_and_contributors_are_stable_and_filtered(self):
        first = [commit('houzi3'), commit('dependabot[bot]', 'Bot'), commit(None)]
        first.extend(commit('houzi3') for _ in range(MODULE.PER_PAGE - len(first)))
        api = FakeAPI([
            {'total_commits': MODULE.PER_PAGE + 3, 'commits': first},
            {'total_commits': MODULE.PER_PAGE + 3,
             'commits': [commit('ZtyGalaxy'), commit('ztygalaxy'), commit('helper')]},
        ])
        self.assertEqual(
            MODULE.contributor_logins(api, 'houzi3/Anmir'),
            ['houzi3', 'ZtyGalaxy', 'helper'],
        )
        compare_calls = [call for call in api.calls if '/compare/' in call[0]]
        self.assertEqual([call[1]['page'] for call in compare_calls], [1, 2])
        self.assertIn('Genymobile:master...houzi3:main', compare_calls[0][0])

    def test_explicit_ref_is_used_in_cross_fork_comparison(self):
        api = FakeAPI([{'total_commits': 1, 'commits': [commit('houzi3')]}])
        MODULE.contributor_logins(api, 'houzi3/Anmir', 'release/next')
        compare = next(path for path, _ in api.calls if '/compare/' in path)
        self.assertIn('houzi3:release%2Fnext', compare)

    def test_both_readmes_update_and_second_run_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = ('Before\n' + MODULE.START_MARKER + '\nold\n' +
                        MODULE.END_MARKER + '\nAfter\n')
            for name in MODULE.README_NAMES:
                (root / name).write_text(original)
            rendered = MODULE.render_contributors(['houzi3', 'ztygalaxy'])
            updates = MODULE.prepare_updates(root, rendered)
            self.assertTrue(MODULE.apply_updates(updates))
            for name in MODULE.README_NAMES:
                text = (root / name).read_text()
                self.assertIn(rendered, text)
                self.assertTrue(text.startswith('Before\n'))
                self.assertTrue(text.endswith('After\n'))
            self.assertFalse(MODULE.apply_updates(MODULE.prepare_updates(root, rendered)))

    def test_check_reports_changes_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = MODULE.START_MARKER + '\nold\n' + MODULE.END_MARKER + '\n'
            for name in MODULE.README_NAMES:
                (root / name).write_text(original)
            updates = MODULE.prepare_updates(root, MODULE.render_contributors(['houzi3']))
            self.assertTrue(MODULE.apply_updates(updates, check=True))
            for name in MODULE.README_NAMES:
                self.assertEqual((root / name).read_text(), original)

    def test_bad_second_readme_does_not_modify_first(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = MODULE.START_MARKER + '\nold\n' + MODULE.END_MARKER + '\n'
            (root / 'README.md').write_text(valid)
            (root / 'README.zh-CN.md').write_text('missing markers\n')
            with self.assertRaisesRegex(ValueError, 'README.zh-CN.md'):
                MODULE.prepare_updates(root, MODULE.render_contributors(['houzi3']))
            self.assertEqual((root / 'README.md').read_text(), valid)

    def test_duplicate_or_reversed_markers_are_rejected(self):
        duplicate = (MODULE.START_MARKER + '\n' + MODULE.START_MARKER + '\n' +
                     MODULE.END_MARKER)
        reversed_markers = MODULE.END_MARKER + '\n' + MODULE.START_MARKER
        with self.assertRaises(ValueError):
            MODULE.replace_generated_block(duplicate, 'new', 'README.md')
        with self.assertRaises(ValueError):
            MODULE.replace_generated_block(reversed_markers, 'new', 'README.md')

    def test_empty_contributor_list_is_rejected(self):
        api = FakeAPI([{'total_commits': 1, 'commits': [commit(None)]}])
        with self.assertRaisesRegex(RuntimeError, 'No linked GitHub contributors'):
            MODULE.contributor_logins(api, 'houzi3/Anmir')


if __name__ == '__main__':
    unittest.main()
