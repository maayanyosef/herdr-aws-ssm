# Minimal test harness. Source this, define test_* functions, call run_tests.
set -uo pipefail
_HS_FAILS=0

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "  FAIL ${msg}: expected [$expected] got [$actual]" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  case "$haystack" in
    *"$needle"*) : ;;
    *) echo "  FAIL ${msg}: [$haystack] does not contain [$needle]" >&2; return 1 ;;
  esac
}

run_tests() {
  local fn
  for fn in $(declare -F | awk '{print $3}' | grep '^test_'); do
    if "$fn"; then echo "PASS $fn"; else echo "FAIL $fn"; _HS_FAILS=$((_HS_FAILS+1)); fi
  done
  [ "$_HS_FAILS" -eq 0 ] || { echo "$_HS_FAILS test(s) failed" >&2; exit 1; }
  echo "all tests passed"
}
