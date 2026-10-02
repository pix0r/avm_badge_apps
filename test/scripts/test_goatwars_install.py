import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/goatwars_install.sh'
HEADER = b'#!/usr/bin/env AtomVM\n\0\0'

class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.firmware = self.root / 'firmware'
        (self.firmware / 'lib/badge').mkdir(parents=True)
        (self.firmware / 'lib/badge/store.ex').touch()
        self.output = self.root / 'output'
        self.log = self.root / 'commands.log'
        self.env = dict(os.environ, AVM_BADGE_PATH=str(self.firmware),
                        GOATWARS_USB_OUTPUT=str(self.output), INSTALL_TEST_LOG=str(self.log),
                        PATH=str(self.bin) + ':' + os.environ['PATH'])
        self.executable('mise', '''#!/usr/bin/env bash
while [[ "$1" != -- ]]; do shift; done
shift
exec "$@"
''')
        self.executable('mix', r'''#!/usr/bin/env python3
import os,sys
from pathlib import Path
with open(os.environ['INSTALL_TEST_LOG'],'a') as log: log.write('mix ' + ' '.join(sys.argv[1:]) + '\n')
if os.environ.get('FAIL_BUILD'): sys.exit(8)
if 'goatwars_usb.exs' in ' '.join(sys.argv):
    if os.environ.get('REQUIRE_FIRMWARE_PROJECT') and Path.cwd() != Path(os.environ['AVM_BADGE_PATH']).resolve():
        sys.exit(9)
    out=Path(sys.argv[-1]);out.mkdir(parents=True,exist_ok=True)
    size=300000 if os.environ.get('OVERSIZE') else 128
    for name in ['firmware.avm','assets.avm']: (out/name).write_bytes(b'#!/usr/bin/env AtomVM\n\0\0'+bytes(size))
''')
        self.executable('esptool', r'''#!/usr/bin/env python3
import os,sys
with open(os.environ['INSTALL_TEST_LOG'],'a') as log: log.write('esptool ' + ' '.join(sys.argv[1:]) + '\n')
sys.exit(int(os.environ.get('FLASH_STATUS','0')))
''')

    def executable(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def run_script(self, *args):
        return subprocess.run(['bash', str(SCRIPT), *args], env=self.env,
                              text=True, capture_output=True)

    def commands(self):
        return self.log.read_text() if self.log.exists() else ''

    def test_default_install_writes_only_assets_and_main_after_build(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.commands().splitlines()
        self.assertTrue(any('atomvm.packbeam' in line for line in lines))
        self.assertTrue(any('badge.assets' in line for line in lines))
        writes = [line for line in lines if line.startswith('esptool ')]
        self.assertEqual(len(writes), 1)
        self.assertIn('0x278000 ' + str(self.output/'assets.avm'), writes[0])
        self.assertIn('0x2B8000 ' + str(self.output/'firmware.avm'), writes[0])
        self.assertNotIn('--port', writes[0])
        self.assertNotIn('erase', writes[0])
        self.assertNotIn('0x9000', writes[0])

    def test_build_only_does_not_open_hardware(self):
        result = self.run_script('--build-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('esptool ', self.commands())

    def test_usb_build_uses_the_selected_firmware_project(self):
        self.env['REQUIRE_FIRMWARE_PROJECT'] = '1'
        result = self.run_script('--build-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('esptool ', self.commands())

    def test_failed_build_never_flashes(self):
        self.env['FAIL_BUILD'] = '1'
        result = self.run_script()
        self.assertEqual(result.returncode, 8)
        self.assertIn('mix ', self.commands())
        self.assertNotIn('esptool ', self.commands())

    def test_oversized_pack_never_flashes(self):
        self.env['OVERSIZE'] = '1'
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('esptool ', self.commands())

    def test_flash_failure_is_propagated(self):
        self.env['FLASH_STATUS'] = '7'
        self.assertEqual(self.run_script().returncode, 7)

    def test_unknown_options_never_build_or_flash(self):
        result = self.run_script('--port', '/dev/anything')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.commands(), '')

if __name__ == '__main__':
    unittest.main()
