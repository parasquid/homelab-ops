#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 && $1 == --config ]] || { printf 'Usage: %s --config PATH\n' "$0" >&2; exit 2; }
config_file=$2
[[ -f $config_file && -r $config_file ]] || { printf 'Configuration unavailable.\n' >&2; exit 1; }
mode=$(stat -c '%a' -- "$config_file")
owner=$(stat -c '%u' -- "$config_file")
if (( (8#$mode & 8#077) != 0 )) || [[ $owner -ne $(id -u) ]]; then
  printf 'Configuration permissions are invalid.\n' >&2
  exit 1
fi

BW_BIN=
BW_CREDENTIAL_FILE=
VAULTWARDEN_URL=
VAULTWARDEN_COLLECTION=
VAULTWARDEN_COLLECTION_ID=${VAULTWARDEN_COLLECTION_ID-}
VAULTWARDEN_ITEM=
VAULTWARDEN_ITEM_ID=${VAULTWARDEN_ITEM_ID-}
HEADER_NAME=Authorization
HEADER_SCHEME=Bearer
# This trusted, protected configuration contains references, not secret values.
# shellcheck disable=SC1090
source "$config_file"
export BW_BIN BW_CREDENTIAL_FILE VAULTWARDEN_URL VAULTWARDEN_COLLECTION_ID
export VAULTWARDEN_ITEM VAULTWARDEN_ITEM_ID HEADER_NAME HEADER_SCHEME

python3 - <<'PY'
import concurrent.futures
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


binary = os.environ.get('BW_BIN', '')
credential_path = Path(os.environ.get('BW_CREDENTIAL_FILE', ''))
server = os.environ.get('VAULTWARDEN_URL', '').rstrip('/')
collection_id = os.environ.get('VAULTWARDEN_COLLECTION_ID', '')
item_name = os.environ.get('VAULTWARDEN_ITEM', '')
item_id = os.environ.get('VAULTWARDEN_ITEM_ID', '')
header_name = os.environ.get('HEADER_NAME', '')
header_scheme = os.environ.get('HEADER_SCHEME', '')
if not all((binary, server, collection_id, item_id, item_name)) or not os.access(binary, os.X_OK):
    fail('Required helper configuration is unavailable.')
if not all(re.fullmatch(r'[0-9a-fA-F-]{36}', x) for x in (collection_id, item_id)):
    fail('Vault reference is invalid.')
if not re.fullmatch(r'[A-Za-z0-9-]+', header_name) or not re.fullmatch(r'[A-Za-z0-9._+-]+', header_scheme):
    fail('Header configuration is invalid.')
try:
    info = credential_path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        fail('Credential file permissions are invalid.')
    lines = credential_path.read_text().splitlines()
    email, master_password = lines[:2]
    if not email or not master_password:
        fail('Credential file is incomplete.')
except (OSError, ValueError):
    fail('Credential file is unavailable.')


def run(args, env=None):
    try:
        result = subprocess.run([binary, *args], check=False, capture_output=True, env=env, timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        fail('Bitwarden CLI operation failed.')
    if result.returncode:
        fail('Bitwarden CLI operation failed.')
    return result.stdout


unlock_env = os.environ.copy()
unlock_env['BW_AGENT_PASSWORD'] = master_password
try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        status_future = pool.submit(run, ['status'])
        session_future = pool.submit(run, ['unlock', '--passwordenv', 'BW_AGENT_PASSWORD', '--raw'], unlock_env)
        status = json.loads(status_future.result())
        session = session_future.result().decode().strip()
except (UnicodeError, json.JSONDecodeError):
    fail('Bitwarden CLI returned invalid state.')
master_password = None
unlock_env.pop('BW_AGENT_PASSWORD', None)
if status.get('serverUrl', '').rstrip('/') != server or status.get('userEmail') != email:
    fail('Bitwarden CLI is logged in to an unexpected server or account.')
if not session or '\n' in session or '\r' in session:
    fail('Bitwarden session is invalid.')

session_env = os.environ.copy()
session_env['BW_SESSION'] = session
try:
    item = json.loads(run(['get', 'item', item_id], session_env))
except (UnicodeError, json.JSONDecodeError):
    fail('Bitwarden CLI returned invalid item data.')
if item.get('id') != item_id or item.get('name') != item_name or collection_id not in (item.get('collectionIds') or []):
    fail('Expected exactly one item in the intended collection.')
password = (item.get('login') or {}).get('password')
if not password or '\n' in password or '\r' in password:
    fail('Vault item has no valid password value.')
print(json.dumps({header_name: f'{header_scheme} {password}'}, separators=(',', ':')))
PY
