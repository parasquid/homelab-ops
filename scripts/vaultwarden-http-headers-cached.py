#!/usr/bin/env python3
"""Return a cached Vaultwarden MCP header, falling back to direct retrieval."""

import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path


def read_cached_header(path):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(0.1)
        connection.connect(str(path))
        connection.sendall(b'GET\n')
        chunks = []
        size = 0
        while size <= 65536:
            chunk = connection.recv(min(4096, 65537 - size))
            if not chunk:
                break
            chunks.append(chunk)
            size += len(chunk)
            if b'\n' in chunk:
                break
    if size > 65536:
        raise ValueError('Cached header response too large')
    data = json.loads(b''.join(chunks))
    if (
        not isinstance(data, dict)
        or set(data) != {'Authorization'}
        or not isinstance(data['Authorization'], str)
        or not data['Authorization'].startswith('Bearer ')
        or len(data['Authorization']) <= len('Bearer ')
    ):
        raise ValueError('Cached header response invalid')
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--socket', type=Path)
    args = parser.parse_args()
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR') or f'/run/user/{os.getuid()}')
    path = args.socket or runtime / 'n8n-mcp-header-cache/headers.sock'
    for delay in (0, 0.05, 0.1):
        if delay:
            time.sleep(delay)
        try:
            data = read_cached_header(path)
        except (OSError, ValueError):
            continue
        sys.stdout.write(json.dumps(data, separators=(',', ':')) + '\n')
        return
    helper = Path(__file__).with_name('vaultwarden-http-headers-fast.sh')
    os.execv(str(helper), [str(helper), '--config', str(args.config)])


if __name__ == '__main__':
    main()
