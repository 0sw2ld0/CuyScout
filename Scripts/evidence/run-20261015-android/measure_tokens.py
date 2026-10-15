#!/usr/bin/env python3
"""pip install tiktoken; run after capturing the receipt's full UiAutomator XML.

Counts response bodies only, without HTTP headers or prompts. observe is the exact
gateway response; the comparison is the raw, uncompressed UiAutomator XML payload.
This is a screen comparison, not a total scenario/model usage benchmark.
"""
import json
from pathlib import Path
import tiktoken

root = Path(__file__).resolve().parent / 'avd'
encoding = tiktoken.get_encoding('cl100k_base')
observe = (root / '05-receipt-observe.json').read_text()
tree = (root / 'receipt-uiautomator.xml').read_text()
assert 'DEMO-0001' in observe and 'DEMO-0001' in tree
counts = {'encoding': 'cl100k_base', 'observe_response_tokens': len(encoding.encode(observe)),
          'full_xml_tokens': len(encoding.encode(tree))}
counts['full_xml_over_observe'] = round(counts['full_xml_tokens'] / counts['observe_response_tokens'], 2)
(root / 'tokens.json').write_text(json.dumps(counts, indent=2) + '\n')
print(json.dumps(counts))
