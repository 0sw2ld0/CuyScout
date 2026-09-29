import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('guard', Path(__file__).resolve().parents[2] / 'Scripts/benchmark_guard.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class LimitsTests(unittest.TestCase):
    def test_call_limit_keeps_cleanup(self):
        limit = guard.Limits(calls=1)
        self.assertTrue(limit.before(0, 'GET', '/status', b''))
        self.assertFalse(limit.before(1, 'GET', '/status', b''))
        self.assertTrue(limit.before(2, 'DELETE', '/session/id', b''))

    def test_deadline(self):
        limit = guard.Limits(seconds=10)
        self.assertTrue(limit.before(0, 'GET', '/status', b''))
        self.assertFalse(limit.before(10, 'POST', '/session/id/actions', b'{}'))
        self.assertEqual(limit.reason, 'time_limit')

    def test_writes_cannot_hide_behind_reads(self):
        limit = guard.Limits()
        for i in range(3):
            self.assertTrue(limit.before(i, 'POST', '/session/id/actions', b'{}'))
            self.assertTrue(limit.before(i, 'GET', '/session/id/observe', b''))
        self.assertFalse(limit.before(4, 'POST', '/session/id/actions', b'{}'))

    def test_strict_server_error_stops_immediately(self):
        limit = guard.Limits(strict=True)
        limit.after('GET', '/session/id/observe', 500, b'error')
        self.assertFalse(limit.before(0, 'POST', '/session/id/actions', b'{}'))
        self.assertEqual(limit.reason, 'cuyscout_server_error')

    def test_repeated_appium_errors_stop_but_single_lookup_miss_does_not(self):
        limit = guard.Limits()
        limit.after('POST', '/session/id/element', 404, b'no element')
        self.assertIsNone(limit.reason)
        limit.after('POST', '/session/id/element', 404, b'no element')
        limit.after('POST', '/session/id/element', 404, b'no element')
        self.assertEqual(limit.reason, 'repeated_error')

    def test_unchanged_observations_ignore_changed_flag(self):
        limit = guard.Limits()
        for i in range(6):
            limit.after('GET', '/session/id/observe', 200, ('{"value":{"stateId":"same","changed":' + ('true' if i == 0 else 'false') + '}}').encode())
        self.assertEqual(limit.reason, 'unchanged_screen_limit')


if __name__ == '__main__':
    unittest.main()
