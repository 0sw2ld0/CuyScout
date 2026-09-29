#!/usr/bin/env python3
"""Recompute wire metrics only; not model context/cost or replay success."""
import json
from pathlib import Path


def metrics(path):
    rows = [json.loads(line) for line in path.read_text().splitlines() if line]
    return {
        'file': path.name,
        'http_calls': len(rows),
        'request_tokens': sum(row['req_tokens'] for row in rows),
        'response_tokens': sum(row['resp_tokens'] for row in rows),
        'wire_tokens': sum(row['req_tokens'] + row['resp_tokens'] for row in rows),
        'http_seconds': round(sum(row['ms'] for row in rows) / 1000, 3),
        'wire_span_seconds': round(rows[-1]['ts'] + rows[-1]['ms'] / 1000 - rows[0]['ts'], 3) if rows else None,
        'http_errors': sum(row['status'] >= 400 for row in rows),
        'observations': sum(row['method'] == 'GET' and row['path'].endswith(('/source', '/observe')) for row in rows),
        'session_deletes': sum(row['method'] == 'DELETE' and row['path'].startswith('/session/') for row in rows),
    }


if __name__ == '__main__':
    root = Path(__file__).resolve().parent
    paths = sorted(root.glob('*-attempt*.jsonl'))
    paths = [path for path in paths if not path.name.endswith('.control.jsonl') and not path.name.startswith('replay-')]
    paths += sorted((root.parent / 'run-20260921-benchmark-prueba-generada').glob('*-sonnet.jsonl'))
    print(json.dumps([metrics(path) for path in paths], indent=2))
