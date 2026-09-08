"""Wallpaper deployment tests use temporary homes and never change the desktop."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('backgrounds', ROOT / 'scripts/install_backgrounds.py')
backgrounds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backgrounds)


class BackgroundTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='backgrounds-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.source = ROOT / 'backgrounds'
        self.files, self.selected = backgrounds.inventory(self.source)
        self.link = self.home / '.local/state/omarchy/current/background'

    def test_new_home_receives_every_background_and_selected_image_without_repo_links(self):
        backgrounds.install(self.source, self.home)
        for relative in self.files:
            installed = self.home / '.config/omarchy/backgrounds' / relative
            self.assertFalse(installed.is_symlink())
            self.assertEqual(installed.read_bytes(), (self.source / relative).read_bytes())
        self.assertEqual(self.link.read_bytes(), (self.source / self.selected).read_bytes())
        self.assertFalse(self.link.readlink().is_absolute())
        self.assertEqual(backgrounds.install(self.source, self.home), [])

    def test_rerun_keeps_a_later_wallpaper_choice_and_additional_images(self):
        backgrounds.install(self.source, self.home)
        custom = self.home / '.config/omarchy/backgrounds/tokyo-night/later.png'
        custom.write_bytes(b'fixture later wallpaper')
        self.link.unlink()
        self.link.symlink_to(custom)
        backgrounds.install(self.source, self.home)
        self.assertEqual(self.link.resolve(), custom)
        self.assertEqual(custom.read_bytes(), b'fixture later wallpaper')

    def test_existing_conflicting_image_and_background_are_preserved_in_backup(self):
        target = self.home / '.config/omarchy/backgrounds' / self.selected
        target.parent.mkdir(parents=True)
        target.write_bytes(b'fixture original image')
        self.link.parent.mkdir(parents=True)
        self.link.write_bytes(b'fixture original background')
        backgrounds.install(self.source, self.home)
        backups = list((self.home / '.local/state/omarchy-setup/backups').glob('backgrounds-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / target.relative_to(self.home)).read_bytes(), b'fixture original image')
        self.assertEqual((backups[0] / self.link.relative_to(self.home)).read_bytes(), b'fixture original background')

    def test_iso_selection_survives_skeleton_copy_and_is_reapplied_after_finalizer_once(self):
        backgrounds.install(self.source, self.home, record=False)
        new_home = self.root / 'new-user'
        shutil.copytree(self.home, new_home, symlinks=True)
        link = new_home / self.link.relative_to(self.home)
        self.assertTrue(link.is_file())
        link.unlink()
        link.write_bytes(b'fixture stock theme selected during finalization')
        backgrounds.install(self.source, new_home)
        self.assertEqual(link.read_bytes(), (self.source / self.selected).read_bytes())

    def test_invalid_bundle_is_rejected_before_writing_any_user_files(self):
        source = self.root / 'bundle'
        source.mkdir()
        manifest = json.loads((self.source / 'manifest.json').read_text())
        manifest['files'][0]['path'] = '../escape.png'
        (source / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            backgrounds.install(source, self.home)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_fresh_iso_build_includes_the_same_background_bundle_and_installer(self):
        spec = importlib.util.spec_from_file_location('prepare_iso', ROOT / 'iso/prepare.py')
        prepare = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(prepare)
        build = self.root / 'build'
        root = build / 'configs/airootfs'
        main = root / 'usr/share/omarchy-iso/orchestrator/main.py'
        main.parent.mkdir(parents=True)
        main.write_text('from .context import InstallContext\n' +
                        '        ("Validating boot setup",      validate_boot),\n')
        (build / 'configs/profiledef.sh').write_text('iso_name="omarchy"\n')
        prepare.prepare(build)
        payload = root / 'usr/share/omarchy-setup-iso'
        self.assertEqual(backgrounds.inventory(payload / 'backgrounds'), (self.files, self.selected))
        self.assertEqual((payload / 'install_backgrounds.py').read_bytes(),
                         (ROOT / 'scripts/install_backgrounds.py').read_bytes())
        self.assertIn('stage_personal_setup', main.read_text())


if __name__ == '__main__':
    unittest.main()
