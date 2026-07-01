#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/assert.sh"
source "$ROOT/lib/common.sh"

test_menu_selects_by_index() {
  local out
  out="$(printf 'alpha\nbeta\ngamma\n' | HS_PICK_INDEX=2 hs_pick 'pick' 2>/dev/null)"
  assert_eq "beta" "$out" second-row || return 1
}

test_menu_first_row() {
  local out
  out="$(printf 'only-one\n' | HS_PICK_INDEX=1 hs_pick 'pick' 2>/dev/null)"
  assert_eq "only-one" "$out" first-row || return 1
}

test_bad_index_fails() {
  if printf 'a\nb\n' | HS_PICK_INDEX=9 hs_pick 'pick' >/dev/null 2>&1; then return 1; fi
}

run_tests
