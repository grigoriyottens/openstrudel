#!/usr/bin/env python3
"""Retention rule for server rollback snapshots."""
import importlib.util, os, pathlib, sys, tempfile, unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('prune', pathlib.Path(__file__).with_name('prune-server-rollbacks.py'))
prune = importlib.util.module_from_spec(spec); spec.loader.exec_module(prune)

class Retention(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = pathlib.Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def snapshot(self, name, healthy):
        path = self.root / name; path.mkdir()
        if healthy: (path / 'healthy.json').write_text('{}')
        return path

    def test_keeps_two_newest_healthy_and_anything_newer(self):
        old = [self.snapshot(f'openstrudel-upgrade-5{i}-2026101{i}T000000Z', True) for i in range(1, 5)]
        failed = self.snapshot('openstrudel-upgrade-51-20261012T010000Z', False)
        pending = self.snapshot('openstrudel-upgrade-56-20261020T000000Z', False)
        kept, removed = prune.plan(old + [failed, pending])
        self.assertEqual(kept, [old[2], old[3], pending])
        self.assertEqual(set(removed), {old[0], old[1], failed})

    def test_removes_nothing_until_two_deployments_were_healthy(self):
        first = self.snapshot('openstrudel-upgrade-43-20261015T000000Z', False)
        second = self.snapshot('openstrudel-upgrade-44-20261016T000000Z', True)
        self.assertEqual(prune.plan([first, second]), ([first, second], []))

    def test_keeps_a_staging_folder_from_a_deployment_in_progress(self):
        kept = [self.snapshot('openstrudel-upgrade-54-20261021T000000Z', True), self.snapshot('openstrudel-upgrade-55-20261022T000000Z', True)]
        old, running, new = (self.root / n for n in ['openstrudel-stage-52-aaa', 'openstrudel-stage-55-bbb', 'openstrudel-stage-56-ccc'])
        for p in (old, running, new): p.mkdir()
        os.utime(old, (1792000000, 1792000000)); os.utime(running, (1792000000, 1792000000))
        self.assertEqual(prune.stale_stages([old, running, new], kept, '55-bbb'), [old])

    def test_keeps_an_image_built_by_a_deployment_in_progress(self):
        kept = [self.snapshot('openstrudel-upgrade-54-20261021T000000Z', True), self.snapshot('openstrudel-upgrade-55-20261022T000000Z', True)]
        created = {'openstrudel:52-aaa': 1792000000, 'openstrudel:before54-20261021T000000Z': 1792000000,
                   'openstrudel:55-bbb': 1792000000, 'openstrudel:56-ccc': 1793000000}
        self.assertEqual(prune.stale_images(created, {'openstrudel:55-bbb'}, kept), ['openstrudel:52-aaa'])

if __name__ == '__main__':
    unittest.main()
