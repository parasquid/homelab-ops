#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

mapfile -d '' publishable < <(git ls-files -z --cached --others --exclude-standard)
if ((${#publishable[@]} == 0)); then
  printf '%s\n' 'publication check: no indexed or nonignored untracked files found' >&2
  exit 1
fi

failed=0
existing=()
for path in "${publishable[@]}"; do
  case "$path" in
    .env.example)
      ;;
    .env|.env.*|.envrc|AGENTS.local.md|*/AGENTS.local.md|inventory.local.yaml|*/inventory.local.yaml|.publication-denylist|*/.publication-denylist|*.local.yaml|*.local.yml|*.secret|*.credentials|private|private/*|secrets|secrets/*|luks-keys|luks-keys/*|*.pem|*.key|*.crt|*.p12|*.pfx|*.dump|*.sql|*.sqlite|*.sqlite3|*.db)
      printf 'publication check: tracked local/private path: %s\n' "$path" >&2
      failed=1
      ;;
  esac
  [[ -f "$path" ]] && existing+=("$path")
done

denylist="$repo_dir/.publication-denylist"
if [[ ! -f "$denylist" ]]; then
  printf '%s\n' 'publication check: missing ignored .publication-denylist; copy and fill .publication-denylist.example first' >&2
  exit 1
fi

while IFS= read -r value || [[ -n "$value" ]]; do
  value=${value%$'\r'}
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  [[ -z "$value" || "$value" == \#* ]] && continue

  for path in "${existing[@]}"; do
    if grep -F -I -q -- "$value" "$path"; then
      printf 'publication check: denylisted value found in %s\n' "$path" >&2
      failed=1
    fi
  done
done < "$denylist"

secret_pattern='-----BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY-----|(^|[[:space:]])(password|passwd|token|api[_-]?key|secret)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_./+=-]{12,}|(ghp_|github_pat_|xox[baprs]-|sk-)[A-Za-z0-9_./+=-]{20,}'
for path in "${existing[@]}"; do
  if grep -E -I -q -- "$secret_pattern" "$path"; then
    printf 'publication check: common secret pattern found in %s\n' "$path" >&2
    failed=1
  fi
done

if ((failed)); then
  exit 1
fi

printf '%s\n' 'publication check: publishable paths and denylisted values are clean'
