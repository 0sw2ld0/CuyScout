"""The real-device smoke must reject reused output before contacting a gateway."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class AndroidSmokeOutputTests(unittest.TestCase):
    def run_smoke(self, output):
        script = Path(__file__).resolve().parents[2] / 'Scripts/smoke_android_device.py'
        return subprocess.run([sys.executable, str(script), '--serial', 'unused',
            '--gateway', 'http://127.0.0.1:1', '--output', str(output),
            '--artifacts', str(output.parent / 'artifacts')], capture_output=True, text=True)

    def test_existing_evidence_is_not_mixed_with_another_run(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'evidence'
            output.mkdir()
            transcript = output / 'http.jsonl'
            transcript.write_bytes(b'previous run\n')
            result = self.run_smoke(output)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn('new or empty directory', result.stderr)
            self.assertNotIn('Traceback', result.stderr)
            self.assertEqual(transcript.read_bytes(), b'previous run\n')
            self.assertEqual(list(output.iterdir()), [transcript])

    def test_output_file_is_rejected_without_overwriting_it(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'evidence'
            output.write_bytes(b'keep this file')
            result = self.run_smoke(output)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn('new or empty directory', result.stderr)
            self.assertNotIn('Traceback', result.stderr)
            self.assertEqual(output.read_bytes(), b'keep this file')
