#!/usr/bin/env python3
"""Keep one Vaultwarden-backed MCP Authorization header in process memory."""

import argparse
import json
import os
import signal
import socket
import stat
import struct
import subprocess
import sys
import threading
from pathlib import Path


def valid_header(data):
    return (
        isinstance(data, dict)
        and set(data) == {'Authorization'}
        and isinstance(data['Authorization'], str)
        and data['Authorization'].startswith('Bearer ')
        and len(data['Authorization']) > len('Bearer ')
    )


def load_header(helper, config):
    result = subprocess.run(
        [str(helper), '--config', str(config)],
        capture_output=True,
        check=False,
        timeout=90,
    )
    if result.returncode:
        raise RuntimeError('Vaultwarden header refresh failed')
    try:
        data = json.loads(result.stdout)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise RuntimeError('Vaultwarden header refresh returned invalid JSON') from error
    if not valid_header(data):
        raise RuntimeError('Vaultwarden header refresh returned an invalid header')
    return json.dumps(data, separators=(',', ':')).encode() + b'\n'


def secure_socket_directory(path):
    parent = path.parent
    parent.mkdir(mode=0o700, parents=False, exist_ok=True)
    info = parent.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError('Socket directory ownership or mode is invalid')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--socket', required=True, type=Path)
    parser.add_argument('--refresh-seconds', type=int, default=900)
    args = parser.parse_args()
    if args.refresh_seconds < 60:
        raise SystemExit('Refresh interval must be at least 60 seconds')
    helper = Path(__file__).with_name('vaultwarden-http-headers.sh')
    os.umask(0o077)
    secure_socket_directory(args.socket)
    if args.socket.exists():
        info = args.socket.lstat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
            raise RuntimeError('Socket path belongs to another file')
        probe = socket.socket(socket.AF_UNIX)
        try:
            probe.settimeout(0.5)
            probe.connect(str(args.socket))
        except (ConnectionRefusedError, FileNotFoundError):
            args.socket.unlink()
        else:
            raise RuntimeError('Header cache is already running')
        finally:
            probe.close()

    cached = load_header(helper, args.config)
    lock = threading.Lock()
    stopped = threading.Event()

    def refresh_loop():
        nonlocal cached
        while not stopped.wait(args.refresh_seconds):
            try:
                refreshed = load_header(helper, args.config)
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                print('Vaultwarden header cache refresh failed', file=sys.stderr)
                continue
            with lock:
                cached = refreshed

    thread = threading.Thread(target=refresh_loop, daemon=True)
    thread.start()
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(str(args.socket))
    os.chmod(args.socket, 0o600)
    socket_inode = args.socket.stat().st_ino
    listener.listen(16)
    listener.settimeout(1)

    def stop(_signum, _frame):
        stopped.set()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        while not stopped.is_set():
            try:
                connection, _ = listener.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(1)
                peer = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
                _pid, uid, _gid = struct.unpack('3i', peer)
                request = b''
                while len(request) < 16 and b'\n' not in request:
                    chunk = connection.recv(16 - len(request))
                    if not chunk:
                        break
                    request += chunk
                if uid != os.getuid() or request != b'GET\n':
                    continue
                with lock:
                    response = cached
                connection.sendall(response)
    finally:
        stopped.set()
        listener.close()
        try:
            if args.socket.stat().st_ino == socket_inode:
                args.socket.unlink()
        except FileNotFoundError:
            pass


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(type(error).__name__ + ': header cache unavailable', file=sys.stderr)
        raise SystemExit(1)
