import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run


class RunnerTests(unittest.TestCase):
    def test_nearest_rank_and_tail_thresholds(self):
        self.assertEqual(run.quantile([9, 1, 4, 2], .5), 2)
        for n in [1, 99, 100, 999, 1000]:
            result = run.stats(list(range(n)))
            self.assertEqual(result['n'], n)
            self.assertEqual(result['p95'] is None, n < 100)
            self.assertEqual(result['p99'] is None, n < 1000)
        self.assertEqual(run.stats(list(range(1000)))['p99'], 989)
        for invalid in [[], [float('nan')], [float('inf')], [-1]]:
            with self.assertRaises(ValueError):
                run.stats(invalid)

    def test_corpus_hash_and_utf16_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = '汉🙂'
            import hashlib
            value = {'cases': [{'id': 'case', 'sha256': hashlib.sha256(source.encode()).hexdigest(), 'utf16Units': 3, 'utf8Bytes': len(source.encode())}]}
            (root / 'case.md').write_text(source)
            run.verify_corpus(value, value, root)
            (root / 'case.md').write_text(source + 'x')
            with self.assertRaises(ValueError):
                run.verify_corpus(value, value, root)

    def test_invalid_coverage_and_missing_native_readiness(self):
        value = {'schema': 1, 'processMemory': {}, 'results': [
            {'settledViewportMeasured': True, 'samples': 10, 'uncoveredSamples': 1, 'fullyMeasuredBeforeTraversal': False}
        ] * 2}
        with self.assertRaises(ValueError):
            run.validate_native(value, 'nativeFast')
        # Diagnostic control is allowed to expose gaps; ordinary and warmed scenarios are not.
        run.validate_native(value, 'nativeFastControl')
        value['results'][0]['uncoveredSamples'] = 0
        with self.assertRaises(ValueError):
            run.validate_native(value, 'nativeFast')
        with self.assertRaises(ValueError):
            run.validate_worker({'schema': 1, 'phase': 'paint', 'case': 'case', 'valid': False, 'result': {}}, 'paint', 'case')

    def test_bad_json_and_timeout_preserve_failed_child(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / 'bad.json'
            records = []
            with self.assertRaises(json.JSONDecodeError):
                run.child([sys.executable, '-c', 'from pathlib import Path; Path(%r).write_text("bad")' % str(output)],
                          output, 'cold', 'case', records)
            self.assertEqual(records[0]['status'], 'failed')
            self.assertEqual(output.read_text(), 'bad')
            with self.assertRaises(RuntimeError):
                run.child([sys.executable, '-c', 'import time; print("partial",flush=True); time.sleep(5)'],
                          root / 'timeout.json', 'cold', 'case', records, timeout=.15)
            self.assertEqual(records[1]['status'], 'failed')
            self.assertIn('partial', records[1]['log'])
            summary = run.summarize(records, [('bad', 'cold', 'case'), ('timeout', 'cold', 'case'), ('missing', 'paint', 'case')])
            self.assertFalse(summary['complete'])
            self.assertEqual(len(summary['failedChildren']), 2)
            self.assertEqual(len(summary['missingChildren']), 1)


if __name__ == '__main__':
    unittest.main()
