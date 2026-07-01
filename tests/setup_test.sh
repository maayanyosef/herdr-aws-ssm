#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/assert.sh"

run_setup() {
  # Point HERDR_PLUGIN_ROOT at the isolated tmp HOME (not the real repo) so a
  # developer's git-ignored repo-root .env can't contaminate these tests. The
  # block assertions only check the ProxyCommand suffix, not the path prefix.
  HOME="$1" HERDR_PLUGIN_ROOT="$1" \
  HERDR_PLUGIN_STATE_DIR="$1/state" HERDR_PLUGIN_CONFIG_DIR="$1/config" \
    bash "$ROOT/bin/setup.sh" --no-doctor
}

test_writes_block_once() {
  local h; h="$(mktemp -d)"
  run_setup "$h" >/dev/null 2>&1 || return 1
  local n
  n="$(grep -c '>>> herdr-aws-ssm >>>' "$h/.ssh/config")"
  assert_eq "1" "$n" one-open-marker || return 1
  assert_contains "$(cat "$h/.ssh/config")" "Host i-* mi-*" host-line || return 1
  assert_contains "$(cat "$h/.ssh/config")" "bin/proxy.sh %h %p %r" proxy-line || return 1
  # ProxyCommand must bake in the config dir so proxy.sh can resolve the AWS
  # profile when ssh runs it for a bare `herdr --remote` (no HERDR_PLUGIN_* env).
  assert_contains "$(cat "$h/.ssh/config")" "HERDR_PLUGIN_CONFIG_DIR=" proxy-env || return 1
}

test_idempotent() {
  local h; h="$(mktemp -d)"
  run_setup "$h" >/dev/null 2>&1 || return 1
  run_setup "$h" >/dev/null 2>&1 || return 1
  local n
  n="$(grep -c '>>> herdr-aws-ssm >>>' "$h/.ssh/config")"
  assert_eq "1" "$n" still-one-block || return 1
}

test_preserves_existing_config() {
  local h; h="$(mktemp -d)"; mkdir -p "$h/.ssh"
  printf 'Host bastion\n  HostName 1.2.3.4\n' > "$h/.ssh/config"
  run_setup "$h" >/dev/null 2>&1
  assert_contains "$(cat "$h/.ssh/config")" "Host bastion" kept-existing || return 1
}

test_writes_config_env() {
  local h; h="$(mktemp -d)"
  run_setup "$h" >/dev/null 2>&1
  [ -f "$h/config/config.env" ] || return 1
}

test_stable_after_three_runs() {
  local h; h="$(mktemp -d)"
  run_setup "$h" >/dev/null 2>&1 || return 1
  run_setup "$h" >/dev/null 2>&1 || return 1
  run_setup "$h" >/dev/null 2>&1 || return 1
  local n
  n="$(grep -c '>>> herdr-aws-ssm >>>' "$h/.ssh/config")"
  assert_eq "1" "$n" one-block-after-three || return 1
  # Confirm no blank lines immediately before the opening marker (no growing preamble).
  local prev="" line
  while IFS= read -r line; do
    if [ "$line" = "# >>> herdr-aws-ssm >>>" ]; then
      assert_eq "" "$prev" no-blank-before-marker || return 1
      break
    fi
    prev="$line"
  done < "$h/.ssh/config"
}

run_tests
