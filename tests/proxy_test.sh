#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/assert.sh"

# Fake aws that answers the two query shapes proxy.sh uses.
mock_aws() {
  local dir="$1"; mkdir -p "$dir"
  cat > "$dir/aws" <<'EOF'
#!/usr/bin/env bash
# describe-instances AZ query -> print an AZ; everything else -> echo args.
for a in "$@"; do
  case "$a" in
    *AvailabilityZone*) echo "us-east-1a"; exit 0 ;;
  esac
done
echo "AWS $*"
exit 0
EOF
  chmod +x "$dir/aws"
}

# Fake aws that returns "None" for the AZ query (simulates wrong region/account).
mock_aws_no_az() {
  local dir="$1"; mkdir -p "$dir"
  cat > "$dir/aws" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    *AvailabilityZone*) echo "None"; exit 0 ;;
  esac
done
echo "AWS $*"
exit 0
EOF
  chmod +x "$dir/aws"
}

test_print_mode_shows_both_commands() {
  local d; d="$(mktemp -d)"; mock_aws "$d/bin"
  local out
  out="$(PATH="$d/bin:/usr/bin:/bin" HS_PROXY_PRINT=1 \
        HERDR_SSM_PROFILE=acct-dev \
        HERDR_SSM_REGION=us-east-1 HERDR_SSM_OSUSER=ubuntu \
        HERDR_PLUGIN_STATE_DIR="$d/state" \
        bash "$ROOT/bin/proxy.sh" i-0123456789abcdef0 22 ubuntu 2>&1)"
  assert_contains "$out" "send-ssh-public-key" push-cmd || return 1
  assert_contains "$out" "AWS-StartSSHSession" ssh-doc || return 1
  assert_contains "$out" "i-0123456789abcdef0" target || return 1
  assert_contains "$out" "us-east-1a" az-resolved || return 1
}

test_generates_keypair() {
  local d; d="$(mktemp -d)"; mock_aws "$d/bin"
  PATH="$d/bin:/usr/bin:/bin" HS_PROXY_PRINT=1 \
    HERDR_SSM_PROFILE=p HERDR_SSM_REGION=us-east-1 HERDR_SSM_OSUSER=ubuntu \
    HERDR_PLUGIN_STATE_DIR="$d/state" \
    bash "$ROOT/bin/proxy.sh" i-abc 22 ubuntu >/dev/null 2>&1
  [ -f "$d/state/id_ed25519" ] && [ -f "$d/state/id_ed25519.pub" ] || return 1
}

test_osuser_from_arg() {
  # $3 (ssh %r) must win over HERDR_SSM_OSUSER so that
  # `herdr --remote ec2-user@i-...` pushes the key for ec2-user, not ubuntu.
  local d; d="$(mktemp -d)"; mock_aws "$d/bin"
  local out
  out="$(PATH="$d/bin:/usr/bin:/bin" HS_PROXY_PRINT=1 \
        HERDR_SSM_PROFILE=p HERDR_SSM_REGION=us-east-1 HERDR_SSM_OSUSER=ubuntu \
        HERDR_PLUGIN_STATE_DIR="$d/state" \
        bash "$ROOT/bin/proxy.sh" i-abc 22 ec2-user 2>&1)"
  assert_contains "$out" "--instance-os-user ec2-user" osuser-from-arg || return 1
}

test_reuses_key_across_runs() {
  # The key must persist across invocations (no per-run regeneration), so
  # herdr's concurrent detection + bridge ssh connections can't race on it.
  local d; d="$(mktemp -d)"; mock_aws "$d/bin"; local st="$d/state"
  PATH="$d/bin:/usr/bin:/bin" HS_PROXY_PRINT=1 HERDR_SSM_PROFILE=p \
    HERDR_SSM_REGION=us-east-1 HERDR_SSM_OSUSER=ubuntu HERDR_PLUGIN_STATE_DIR="$st" \
    bash "$ROOT/bin/proxy.sh" i-abc 22 ubuntu >/dev/null 2>&1
  local first; first="$(cat "$st/id_ed25519.pub")"
  PATH="$d/bin:/usr/bin:/bin" HS_PROXY_PRINT=1 HERDR_SSM_PROFILE=p \
    HERDR_SSM_REGION=us-east-1 HERDR_SSM_OSUSER=ubuntu HERDR_PLUGIN_STATE_DIR="$st" \
    bash "$ROOT/bin/proxy.sh" i-abc 22 ubuntu >/dev/null 2>&1
  local second; second="$(cat "$st/id_ed25519.pub")"
  assert_eq "$first" "$second" key-persists || return 1
}

test_az_none_fails() {
  local d; d="$(mktemp -d)"; mock_aws_no_az "$d/bin"
  if PATH="$d/bin:/usr/bin:/bin" HS_PROXY_PRINT=1 \
       HERDR_SSM_PROFILE=p HERDR_SSM_REGION=us-east-1 HERDR_SSM_OSUSER=ubuntu \
       HERDR_PLUGIN_STATE_DIR="$d/state" \
       bash "$ROOT/bin/proxy.sh" i-abc 22 ubuntu >/dev/null 2>&1; then
    return 1
  fi
}

run_tests
