#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/assert.sh"

# Build a fake PATH with chosen binaries present.
mkbin() {
  local dir="$1"; shift; mkdir -p "$dir"
  local b
  for b in "$@"; do printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/$b"; chmod +x "$dir/$b"; done
}

test_all_present_ok() {
  local d; d="$(mktemp -d)"; mkbin "$d/bin" aws session-manager-plugin herdr fzf
  local out
  out="$(PATH="$d/bin:/usr/bin:/bin" HS_DOCTOR_SKIP_AWS=1 \
        HERDR_PLUGIN_CONFIG_DIR="$d" bash "$ROOT/bin/doctor.sh" 2>&1)" || return 1
  assert_contains "$out" "aws" aws-checked || return 1
}

test_missing_hard_dep_fails() {
  local d; d="$(mktemp -d)"; mkbin "$d/bin" aws herdr fzf   # no session-manager-plugin
  if PATH="$d/bin:/usr/bin:/bin" HS_DOCTOR_SKIP_AWS=1 \
     HERDR_PLUGIN_CONFIG_DIR="$d" bash "$ROOT/bin/doctor.sh" >/dev/null 2>&1; then
    return 1
  fi
}

run_tests
