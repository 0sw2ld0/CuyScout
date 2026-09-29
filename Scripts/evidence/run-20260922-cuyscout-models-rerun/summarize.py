#!/usr/bin/env python3
"""Recompute protocol traffic; never interpret partial runs as token advantages."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
result = []
for path in sorted(root.glob('*.jsonl')):
    if path.name.endswith('.control.jsonl'):
        continue
    rows = [json.loads(line) for line in path.read_text().splitlines() if line]
    result.append({
        'file': path.name,
        'phase': 'replay' if path.name.startswith('replay-') else 'exploration',
        'calls': len(rows),
        'request_tokens': sum(x['req_tokens'] for x in rows),
        'response_tokens': sum(x['resp_tokens'] for x in rows),
        'wire_tokens': sum(x['req_tokens'] + x['resp_tokens'] for x in rows),
        'http_seconds': round(sum(x['ms'] for x in rows) / 1000, 3),
        'wire_span_seconds': round(rows[-1]['ts'] + rows[-1]['ms']/1000 - rows[0]['ts'], 3) if rows else None,
        'http_errors': sum(x['status'] >= 400 for x in rows),
        'deletes': sum(x['method'] == 'DELETE' for x in rows)
    })
print(json.dumps(result, indent=2))
