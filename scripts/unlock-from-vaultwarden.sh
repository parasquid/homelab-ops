#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: unlock-from-vaultwarden.sh --config PATH [--test]

Source a trusted, protected deployment configuration, retrieve one exact
Vaultwarden login-item password, decode it in memory, and pass it to a remote
cryptsetup process over standard input.

  --config PATH  Required protected configuration file.
  --test         Validate the key against the LUKS header without opening it.
  --help         Show this help.
EOF
}

config_file=
test_only=false

while (($#)); do
  case $1 in
    --config)
      (($# >= 2)) || { printf '%s\n' '--config requires a path.' >&2; exit 2; }
      config_file=$2
      shift 2
      ;;
    --test)
      test_only=true
      shift
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

[[ -n ${config_file} ]] || { printf '%s\n' '--config is required.' >&2; exit 2; }
[[ -f ${config_file} && -r ${config_file} ]] || {
  printf '%s\n' 'Configuration must be a readable regular file.' >&2
  exit 1
}

config_mode=$(stat -c '%a' -- "${config_file}")
config_owner=$(stat -c '%u' -- "${config_file}")
if (( (8#${config_mode} & 8#077) != 0 )) || [[ ${config_owner} -ne $(id -u) ]]; then
  printf '%s\n' 'Configuration must be owned by the current user with no group or other permissions.' >&2
  exit 1
fi

# The configuration is executable shell input. Source only a file created and
# controlled by the operator. It must contain references, never secret values.
BW_BIN=
BW_CREDENTIAL_FILE=
VAULTWARDEN_URL=
VAULTWARDEN_COLLECTION=
VAULTWARDEN_ITEM=
SECRET_ENCODING=
EXPECTED_DECODED_BYTES=
VM_HOST=
VM_USER=
LUKS_DEVICE=
LUKS_MAPPER=
DATA_MOUNT=
SSH_CONNECT_TIMEOUT=
REMOTE_POST_UNLOCK_COMMAND=
# shellcheck disable=SC1090
source "${config_file}"

: "${BW_BIN:?Set BW_BIN in the configuration}"
: "${BW_CREDENTIAL_FILE:?Set BW_CREDENTIAL_FILE in the configuration}"
: "${VAULTWARDEN_URL:?Set VAULTWARDEN_URL in the configuration}"
: "${VAULTWARDEN_COLLECTION:?Set VAULTWARDEN_COLLECTION in the configuration}"
: "${VAULTWARDEN_ITEM:?Set VAULTWARDEN_ITEM in the configuration}"
: "${SECRET_ENCODING:?Set SECRET_ENCODING in the configuration}"
: "${EXPECTED_DECODED_BYTES:?Set EXPECTED_DECODED_BYTES in the configuration}"
: "${VM_HOST:?Set VM_HOST in the configuration}"
: "${VM_USER:?Set VM_USER in the configuration}"
: "${LUKS_DEVICE:?Set LUKS_DEVICE in the configuration}"
: "${LUKS_MAPPER:?Set LUKS_MAPPER in the configuration}"
: "${DATA_MOUNT:?Set DATA_MOUNT in the configuration}"

SSH_CONNECT_TIMEOUT=${SSH_CONNECT_TIMEOUT:-12}
REMOTE_POST_UNLOCK_COMMAND=${REMOTE_POST_UNLOCK_COMMAND:-}
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

[[ ${EXPECTED_DECODED_BYTES} =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' 'EXPECTED_DECODED_BYTES must be a positive integer.' >&2
  exit 1
}
[[ ${SSH_CONNECT_TIMEOUT} =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' 'SSH_CONNECT_TIMEOUT must be a positive integer.' >&2
  exit 1
}
[[ ${VM_USER} =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || {
  printf '%s\n' 'VM_USER contains unsupported characters.' >&2
  exit 1
}
[[ ${VM_HOST} =~ ^[A-Za-z0-9._:-]+$ ]] || {
  printf '%s\n' 'VM_HOST contains unsupported characters.' >&2
  exit 1
}
[[ ${LUKS_DEVICE} =~ ^/dev/[A-Za-z0-9._/+:-]+$ ]] || {
  printf '%s\n' 'LUKS_DEVICE must be a simple absolute device path.' >&2
  exit 1
}
[[ ${LUKS_MAPPER} =~ ^[A-Za-z0-9._+-]+$ ]] || {
  printf '%s\n' 'LUKS_MAPPER contains unsupported characters.' >&2
  exit 1
}
[[ ${DATA_MOUNT} =~ ^/[A-Za-z0-9._/+:-]+$ ]] || {
  printf '%s\n' 'DATA_MOUNT must be a simple absolute path.' >&2
  exit 1
}

case ${SECRET_ENCODING} in
  base64)
    decode_secret() { base64 --decode; }
    ;;
  *)
    printf 'Unsupported SECRET_ENCODING: %s\n' "${SECRET_ENCODING}" >&2
    exit 1
    ;;
esac

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
trap 'unset BW_SESSION encoded_secret' EXIT

"${BW_BIN}" --quiet sync

encoded_secret=$(
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
    raise SystemExit("Expected exactly one collection and one key item")
item = matches[0]
if collection_ids[0] not in (item.get("collectionIds") or []):
    raise SystemExit("Key item is outside the expected collection")
password = (item.get("login") or {}).get("password")
if not password:
    raise SystemExit("Key item has no password value")
print(password, end="")
PY
)

decoded_size=$(printf '%s' "${encoded_secret}" | decode_secret | wc -c)
if [[ ${decoded_size} -ne ${EXPECTED_DECODED_BYTES} ]]; then
  printf '%s\n' 'The retrieved value decoded to an unexpected byte length.' >&2
  exit 1
fi

ssh_opts=(-o BatchMode=yes -o "ConnectTimeout=${SSH_CONNECT_TIMEOUT}" -o LogLevel=ERROR)
target=${VM_USER}@${VM_HOST}
mapper_path=/dev/mapper/${LUKS_MAPPER}

if [[ ${test_only} == true ]]; then
  # shellcheck disable=SC2029 # Validated deployment values are intentionally sent to the guest.
  printf '%s' "${encoded_secret}" | decode_secret | \
    ssh "${ssh_opts[@]}" "${target}" \
      "sudo -n cryptsetup open --test-passphrase --key-file=- --keyfile-size='${EXPECTED_DECODED_BYTES}' '${LUKS_DEVICE}'"
  printf '%s\n' 'Vaultwarden LUKS key passed the header test.'
  exit 0
fi

# shellcheck disable=SC2029 # Validated deployment values are intentionally sent to the guest.
if ! ssh "${ssh_opts[@]}" "${target}" "test -e '${mapper_path}'"; then
  # shellcheck disable=SC2029 # Validated deployment values are intentionally sent to the guest.
  printf '%s' "${encoded_secret}" | decode_secret | \
    ssh "${ssh_opts[@]}" "${target}" \
      "sudo -n cryptsetup open --allow-discards --key-file=- --keyfile-size='${EXPECTED_DECODED_BYTES}' '${LUKS_DEVICE}' '${LUKS_MAPPER}'"
fi
unset encoded_secret

# shellcheck disable=SC2029 # Validated deployment values are intentionally sent to the guest.
ssh "${ssh_opts[@]}" "${target}" "
  set -eu
  if ! findmnt -rn -M '${DATA_MOUNT}' >/dev/null; then
    sudo -n mount '${DATA_MOUNT}'
  fi
  test \"\$(findmnt -rn -M '${DATA_MOUNT}' -o SOURCE)\" = '${mapper_path}'
"

if [[ -n ${REMOTE_POST_UNLOCK_COMMAND} ]]; then
  printf '%s\n' "${REMOTE_POST_UNLOCK_COMMAND}" | \
    ssh "${ssh_opts[@]}" "${target}" 'bash -se'
fi

printf 'Mapper %s is unlocked and mounted at %s.\n' "${LUKS_MAPPER}" "${DATA_MOUNT}"
