"""Runtime packaging tests; do not execute or change REAPER."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('runtime_release', ROOT / 'scripts/runtime_release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class RuntimeReleaseTests(unittest.TestCase):
    def test_install_archive_contains_runtime_and_legal_notice_only(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as folder:
            result = release.build(ROOT, 'HEAD', Path(folder))
            with zipfile.ZipFile(result['archive']) as archive:
                paths = archive.namelist()
                self.assertIn('ReaSkiiPicker/ReaSkii_Picker.lua', paths)
                self.assertIn('ReaSkiiPicker/vendor/json-LICENSE', paths)
                self.assertFalse(any('/tests/' in p or '/scripts/' in p or p.endswith('README.md') for p in paths))
                self.assertFalse(any(p.endswith(('.dll', '.key', '.json', '.png')) for p in paths))
                for path in paths:
                    relative = path.removeprefix('ReaSkiiPicker/')
                    self.assertEqual(archive.read(path), release.git(ROOT, 'show', result['commit'] + ':' + relative))

    def test_build_is_deterministic_and_ignores_uncommitted_feature(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as folder:
            first = release.build(ROOT, 'HEAD', Path(folder) / 'first')
            second = release.build(ROOT, 'HEAD', Path(folder) / 'second')
            self.assertEqual(first['sha256'], second['sha256'])
            committed_entry = release.git(ROOT, 'show', 'HEAD:ReaSkii_Picker.lua').decode()
            self.assertIn('-- @version ' + first['version'], committed_entry)

    def test_verified_frozen_runtime_matches(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as folder:
            built = release.build(ROOT, 'HEAD', Path(folder))
            verified = release.verify_evidence(built, ROOT / 'qa/package-report.json')
            self.assertGreater(verified['total_checks'], 0)

    def test_unverified_or_modified_archive_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as folder:
            built = release.build(ROOT, 'HEAD', Path(folder))
            bad = Path(folder) / 'bad-report.json'
            bad.write_text(json.dumps({'installed_on_daily_reaper': False}))
            with self.assertRaises((ValueError, AssertionError)):
                release.verify_evidence(built, bad)


if __name__ == '__main__':
    unittest.main()
