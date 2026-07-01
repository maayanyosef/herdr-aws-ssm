#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/assert.sh"

test_license_present_mit() {
  [ -f "$ROOT/LICENSE" ] || return 1
  assert_contains "$(cat "$ROOT/LICENSE")" "MIT License" mit || return 1
  assert_contains "$(cat "$ROOT/LICENSE")" "herdr-aws-ssm contributors" holder || return 1
}

test_no_committed_secrets() {
  # Scan tracked files for obvious credential material. Must find nothing.
  local hits
  hits="$(cd "$ROOT" && git grep -nIE \
    'AKIA[0-9A-Z]{16}|aws_secret_access_key|-----BEGIN [A-Z ]*PRIVATE KEY-----' \
    -- . ':!tests/release_test.sh' 2>/dev/null || true)"
  if [ -n "$hits" ]; then echo "  FAIL secret-like content: $hits" >&2; return 1; fi
}

test_no_account_specific_identifiers() {
  # Public repo must not leak org-specific account IDs or SSO profile names.
  # Scans tracked files for a raw 12-digit AWS account id or an SSO-style
  # "AdministratorAccess-<account>" profile. (The pattern lives here, not any
  # real value.) This test file itself is excluded from the scan.
  # Blocks org account IDs, SSO-style profile names, and the maintainer's
  # personal name. The GitHub repo handle (maayanyosef) is allowed — it's the
  # public repo location referenced by the install command.
  local hits
  hits="$(cd "$ROOT" && git grep -nIiE \
    'AdministratorAccess-[0-9]{12}|maayan[ ._-]+yosef' \
    -- . ':!tests/release_test.sh' 2>/dev/null || true)"
  if [ -n "$hits" ]; then echo "  FAIL account-specific content: $hits" >&2; return 1; fi
}

test_manifest_present_for_marketplace() {
  [ -f "$ROOT/herdr-plugin.toml" ] || return 1
}

test_env_example_tracked_env_ignored() {
  cd "$ROOT" || return 1
  git ls-files --error-unmatch .env.example >/dev/null 2>&1 || { echo "  FAIL .env.example not tracked" >&2; return 1; }
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then echo "  FAIL .env is tracked" >&2; return 1; fi
  git check-ignore -q .env || { echo "  FAIL .env not git-ignored" >&2; return 1; }
}

run_tests
