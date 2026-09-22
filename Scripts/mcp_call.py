#!/usr/bin/env python3
"""Minimal MCP stdio client for tool-only evaluations without a native MCP host.

Only handles framing/transport: no app knowledge, actions, retries or file discovery.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gateway', required=True)
    parser.add_argument('--binary', default=str(Path(__file__).resolve().parents[1] / '.build/debug/cuyscout-mcp'))
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument('--method', choices=['initialize', 'tools/list'])
    choice.add_argument('--tool')
    parser.add_argument('--args', default='{}', help='JSON object of tool arguments only (no JSON-RPC envelope)')
    args = parser.parse_args()
    try:
        arguments = json.loads(args.args)
        if not isinstance(arguments, dict):
            raise ValueError('expected an object')
    except (ValueError, TypeError) as error:
        parser.error(f'Invalid --args JSON object: {error}. Nothing executed.')
    request = {'jsonrpc': '2.0', 'id': 1, 'method': args.method or 'tools/call',
               'params': {'name': args.tool, 'arguments': arguments} if args.tool else {}}
    if args.method == 'initialize':
        request['params'] = {'protocolVersion': '2024-11-05', 'capabilities': {},
                             'clientInfo': {'name': 'cuyscout-stdio-client', 'version': '1'}}
    try:
        result = subprocess.run([args.binary], input=json.dumps(request) + '\n',
                                text=True, capture_output=True, timeout=150,
                                env=dict(os.environ, CUYSCOUT_GATEWAY_URL=args.gateway))
    except subprocess.TimeoutExpired:
        print('MCP transport timed out; execution outcome unknown. Observe before any retry.', file=sys.stderr)
        return 1
    except OSError as error:
        print(f'Could not start MCP process: {error}', file=sys.stderr)
        return 1
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == '__main__':
    sys.exit(main())
