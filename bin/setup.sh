#!/usr/bin/env bash
set -euo pipefail
HS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HS_DIR/lib/common.sh"
hs_load_config

ROOT="${HERDR_PLUGIN_ROOT:-$HS_DIR}"
STATE="${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr-aws-ssm}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/herdr-aws-ssm}"
SSH_CONFIG="$HOME/.ssh/config"
BEGIN='# >>> herdr-aws-ssm >>>'
END='# <<< herdr-aws-ssm <<<'

mkdir -p "$STATE" "$CONFIG_DIR" "$(dirname "$SSH_CONFIG")"
chmod 700 "$STATE"

# Write config.env if missing.
if [ ! -f "$CONFIG_DIR/config.env" ]; then
  cat > "$CONFIG_DIR/config.env" <<EOF
HERDR_SSM_PROFILES="$HERDR_SSM_PROFILES"
HERDR_SSM_REGION="$HERDR_SSM_REGION"
HERDR_SSM_OSUSER="$HERDR_SSM_OSUSER"
EOF
fi

# Concrete default login user for the bare `herdr --remote i-...` path. The
# HERDR_SSM_OSUSER "auto" sentinel can't be written as an ssh User, so fall back
# to ec2-user here; the connect action auto-detects and overrides per-connection.
default_user="$HERDR_SSM_OSUSER"
[ "$default_user" = "auto" ] && default_user="ec2-user"

# Build managed block.
block="$(cat <<EOF
$BEGIN
Host i-* mi-*
  User $default_user
  IdentityFile $STATE/id_ed25519
  ProxyCommand $ROOT/bin/proxy.sh %h %p %r
  StrictHostKeyChecking accept-new
$END
EOF
)"

touch "$SSH_CONFIG"; chmod 600 "$SSH_CONFIG"
tmp="$(mktemp)"
# Copy everything outside the managed block into tmp.
awk -v b="$BEGIN" -v e="$END" '
  $0==b {skip=1; next}
  $0==e {skip=0; next}
  skip!=1 {print}
' "$SSH_CONFIG" > "$tmp"
# Write atomically to a second temp file, then mv over $SSH_CONFIG.
# This avoids zeroing the user's ssh config if interrupted mid-write.
out="$(mktemp)"
if [ -s "$tmp" ]; then
  # Existing content: separate it from the new block with a blank line.
  printf '%s\n\n%s\n' "$(cat "$tmp")" "$block" > "$out"
else
  # Fresh/empty config: no leading blank lines.
  printf '%s\n' "$block" > "$out"
fi
rm -f "$tmp"
chmod 600 "$out"
mv "$out" "$SSH_CONFIG"
hs_log "herdr-aws-ssm: ssh config updated ($SSH_CONFIG)"

if [ "${1:-}" != "--no-doctor" ] && [ -x "$ROOT/bin/doctor.sh" ]; then
  "$ROOT/bin/doctor.sh" || true
fi
