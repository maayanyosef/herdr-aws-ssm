#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/assert.sh"

DEV="i-0aaaaaaaaaaaaaaa1"
PROD="i-0bbbbbbbbbbbbbbb2"

# Fake aws + herdr on PATH, plus a generic config (no real accounts). The mock
# answers: instance listing, SSM ping, per-instance ImageId, and describe-images
# (so the os-user auto-detect resolves ubuntu for dev, ec2-user for prod).
mock_env() {
  local d="$1"; mkdir -p "$d/bin" "$d/config"
  printf 'HERDR_SSM_PROFILES="dev=acct-dev prod=acct-prod"\n' > "$d/config/config.env"
  cat > "$d/bin/aws" <<EOF
#!/usr/bin/env bash
prof=""; sub=""; iid=""; ami=""
args=("\$@")
for ((i=0;i<\${#args[@]};i++)); do
  case "\${args[\$i]}" in
    --profile) prof="\${args[\$((i+1))]}" ;;
    --instance-ids) iid="\${args[\$((i+1))]}" ;;
    --image-ids) ami="\${args[\$((i+1))]}" ;;
    describe-instances) sub="di" ;;
    describe-instance-information) sub="ssm" ;;
    describe-images) sub="img" ;;
  esac
done
case "\$sub" in
  ssm) printf '$DEV\tOnline\n$PROD\tOnline\n' ;;
  img)
    case "\$ami" in
      ami-ubuntu*) printf 'ubuntu-jammy-22.04\tCanonical, Ubuntu\tLinux/UNIX\n' ;;
      ami-amzn*)   printf 'amzn2-ami-hvm-2.0\tAmazon Linux 2\tLinux/UNIX\n' ;;
      *)           printf 'mystery\tmystery\tLinux/UNIX\n' ;;
    esac ;;
  di)
    if [ -n "\$iid" ]; then
      case "\$iid" in
        $DEV)  echo "ami-ubuntu-123" ;;
        $PROD) echo "ami-amzn-456" ;;
        *)     echo "None" ;;
      esac
    else
      case "\$prof" in
        acct-dev)  printf '$DEV\tt3.medium\tus-east-1a\tapi-server\n' ;;
        acct-prod) printf '$PROD\tt3.large\tus-east-1b\tprod-api\n' ;;
      esac
    fi ;;
esac
exit 0
EOF
  chmod +x "$d/bin/aws"
  printf '#!/usr/bin/env bash\necho "HERDR \$*"\n' > "$d/bin/herdr"; chmod +x "$d/bin/herdr"
}

test_dryrun_dev_pick_detects_ubuntu() {
  local d; d="$(mktemp -d)"; mock_env "$d"
  local out
  out="$(PATH="$d/bin:/usr/bin:/bin" HS_PICK_INDEX=1 \
        HERDR_PLUGIN_CONFIG_DIR="$d/config" \
        bash "$ROOT/bin/connect.sh" --dry-run 2>/dev/null)"
  assert_contains "$out" "WOULD: herdr --remote ubuntu@$DEV" launch || return 1
  assert_contains "$out" "profile=acct-dev" dev-profile || return 1
}

test_prod_requires_confirm() {
  local d; d="$(mktemp -d)"; mock_env "$d"
  # Pick row 2 (prod) with wrong confirmation -> must abort non-zero, and the
  # abort must come from the prod gate specifically (assert its stderr message).
  local err
  err="$(PATH="$d/bin:/usr/bin:/bin" HS_PICK_INDEX=2 HS_CONFIRM=no \
        HERDR_PLUGIN_CONFIG_DIR="$d/config" \
        bash "$ROOT/bin/connect.sh" --dry-run 2>&1 >/dev/null)" && return 1
  assert_contains "$err" "prod connection aborted" gate-message || return 1
}

test_prod_proceeds_detects_ec2_user() {
  local d; d="$(mktemp -d)"; mock_env "$d"
  local out
  out="$(PATH="$d/bin:/usr/bin:/bin" HS_PICK_INDEX=2 HS_CONFIRM=yes-prod \
        HERDR_PLUGIN_CONFIG_DIR="$d/config" \
        bash "$ROOT/bin/connect.sh" --dry-run 2>/dev/null)"
  assert_contains "$out" "WOULD: herdr --remote ec2-user@$PROD" prod-launch || return 1
}

run_tests
