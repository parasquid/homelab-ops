#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: vaultwarden-http-headers.sh --config PATH

Source a trusted, protected deployment configuration, retrieve one exact
Vaultwarden login-item password, and print the HTTP header JSON expected by an
MCP client's http_headers_helper setting.

  --config PATH  Required protected configuration file.
  --help         Show this help.
EOF
}

config_file=
while (($#)); do
  case $1 in
    --config)
      (($# >= 2)) || { printf '%s\n' '--config requires a path.' >&2; exit 2; }
      config_file=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n ${config_file} && -f ${config_file} && -r ${config_file} ]] || {
  printf '%s\n' 'A readable regular configuration file is required.' >&2
  exit 1
}

config_mode=$(stat -c '%a' -- "${config_file}")
config_owner=$(stat -c '%u' -- "${config_file}")
if (( (8#${config_mode} & 8#077) != 0 )) || [[ ${config_owner} -ne $(id -u) ]]; then
  printf '%s\n' 'Configuration must be owned by the current user with no group or other permissions.' >&2
  exit 1
fi

# The configuration is executable shell input. Source only a file created and
# controlled by the operator. It contains references, never secret values.
BW_BIN=
BW_CREDENTIAL_FILE=
VAULTWARDEN_URL=
VAULTWARDEN_COLLECTION=
VAULTWARDEN_ITEM=
HEADER_NAME=Authorization
HEADER_SCHEME=Bearer
# shellcheck disable=SC1090
source "${config_file}"

: "${BW_BIN:?Set BW_BIN in the configuration}"
: "${BW_CREDENTIAL_FILE:?Set BW_CREDENTIAL_FILE in the configuration}"
: "${VAULTWARDEN_URL:?Set VAULTWARDEN_URL in the configuration}"
: "${VAULTWARDEN_COLLECTION:?Set VAULTWARDEN_COLLECTION in the configuration}"
: "${VAULTWARDEN_ITEM:?Set VAULTWARDEN_ITEM in the configuration}"

VAULTWARDEN_URL=${VAULTWARDEN_URL%/}
[[ -x ${BW_BIN} ]] || { printf '%s\n' 'BW_BIN is not executable.' >&2; exit 1; }
[[ -f ${BW_CREDENTIAL_FILE} && -r ${BW_CREDENTIAL_FILE} ]] || {
  printf '%s\n' 'The Vaultwarden credential file is not readable.' >&2
  exit 1
}

credential_mode=$(stat -c '%a' -- "${BW_CREDENTIAL_FILE}")
credential_owner=$(stat -c '%u' -- "${BW_CREDENTIAL_FILE}")
if (( (8#${credential_mode} & 8#077) != 0 )) || [[ ${credential_owner} -ne $(id -u) ]]; then
  printf '%s\n' 'The credential file must be owned by the current user with no group or other permissions.' >&2
  exit 1
fi

[[ ${HEADER_NAME} =~ ^[A-Za-z0-9-]+$ ]] || {
  printf '%s\n' 'HEADER_NAME contains unsupported characters.' >&2
  exit 1
}
[[ ${HEADER_SCHEME} =~ ^[A-Za-z0-9._+-]+$ ]] || {
  printf '%s\n' 'HEADER_SCHEME contains unsupported characters.' >&2
  exit 1
}

agent_email=$(sed -n '1p' "${BW_CREDENTIAL_FILE}")
agent_password=$(sed -n '2p' "${BW_CREDENTIAL_FILE}")
[[ -n ${agent_email} && -n ${agent_password} ]] || {
  printf '%s\n' 'The credential file must contain email on line 1 and master password on line 2.' >&2
  exit 1
}

mapfile -t state < <(
  "${BW_BIN}" status | python3 -c '
import json, sys
value = json.load(sys.stdin)
print(value.get("status") or "unknown")
print((value.get("serverUrl") or "").rstrip("/"))
print(value.get("userEmail") or "")
'
)

[[ ${#state[@]} -eq 3 ]] || {
  printf '%s\n' 'Could not read Bitwarden CLI state.' >&2
  exit 1
}
if [[ ${state[0]} != unauthenticated && ${state[1]} != "${VAULTWARDEN_URL}" ]]; then
  printf '%s\n' 'Bitwarden CLI is logged in against an unexpected server.' >&2
  exit 1
fi
if [[ ${state[0]} == unauthenticated ]]; then
  "${BW_BIN}" --quiet config server "${VAULTWARDEN_URL}"
  export BW_AGENT_PASSWORD=${agent_password}
  "${BW_BIN}" --quiet login "${agent_email}" --passwordenv BW_AGENT_PASSWORD
elif [[ ${state[2]} != "${agent_email}" ]]; then
  printf '%s\n' 'Bitwarden CLI is logged in as an unexpected account.' >&2
  exit 1
fi

export BW_AGENT_PASSWORD=${agent_password}
BW_SESSION=$("${BW_BIN}" unlock --passwordenv BW_AGENT_PASSWORD --raw)
export BW_SESSION
unset BW_AGENT_PASSWORD agent_password
trap 'unset BW_SESSION header_value' EXIT

"${BW_BIN}" --quiet sync
header_value=$(
  python3 - "${BW_BIN}" "${VAULTWARDEN_COLLECTION}" "${VAULTWARDEN_ITEM}" <<'PY'
import json
import subprocess
import sys

bw, collection_name, item_name = sys.argv[1:4]
collections = json.loads(
    subprocess.run([bw, "list", "collections"], check=True, capture_output=True, text=True).stdout
)
items = json.loads(
    subprocess.run(
        [bw, "list", "items", "--search", item_name],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
)
collection_ids = [item["id"] for item in collections if item.get("name") == collection_name]
matches = [item for item in items if item.get("name") == item_name]
if len(collection_ids) != 1 or len(matches) != 1:
    raise SystemExit("Expected exactly one collection and one item")
item = matches[0]
if collection_ids[0] not in (item.get("collectionIds") or []):
    raise SystemExit("Item is outside the expected collection")
password = (item.get("login") or {}).get("password")
if not password or "\n" in password or "\r" in password:
    raise SystemExit("Item has no valid single-line password value")
print(password, end="")
PY
)

printf '%s' "${header_value}" | python3 -c '
import json, sys
header, scheme = sys.argv[1:3]
value = sys.stdin.read()
json.dump({header: f"{scheme} {value}"}, sys.stdout, separators=(",", ":"))
' "${HEADER_NAME}" "${HEADER_SCHEME}"
printf '\n'
