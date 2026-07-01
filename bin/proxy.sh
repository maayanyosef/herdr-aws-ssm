#!/usr/bin/env bash
set -euo pipefail
HS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HS_DIR/lib/common.sh"
hs_load_config

host="${1:?instance-id required}"
port="${2:-22}"
# ssh's remote user (%r) wins; else the configured default. The connect action
# resolves "auto" before launching, but guard here in case of a bare invocation.
osuser="${3:-${HERDR_SSM_OSUSER:-ec2-user}}"
[ "$osuser" = "auto" ] && osuser="ec2-user"
region="${HERDR_SSM_REGION:-us-east-1}"
state="${HERDR_PLUGIN_STATE_DIR:-$HOME/.local/state/herdr-aws-ssm}"
key="$state/id_ed25519"

mkdir -p "$state"; chmod 700 "$state"

# Resolve owning profile: prefer env, else probe configured profiles.
resolve_profile() {
  if [ -n "${HERDR_SSM_PROFILE:-}" ]; then printf '%s' "$HERDR_SSM_PROFILE"; return 0; fi
  local env profile
  for env in $(hs_envs); do
    profile="$(hs_profile_for_env "$env")"
    if aws ec2 describe-instances --instance-ids "$host" \
         --profile "$profile" --region "$region" \
         --query 'Reservations[0].Instances[0].InstanceId' --output text >/dev/null 2>&1; then
      printf '%s' "$profile"; return 0
    fi
  done
  return 1
}
profile="$(resolve_profile)" || { hs_err "cannot resolve AWS profile for $host"; exit 1; }

# Ensure a local keypair exists (generate once, then reuse). The *ephemeral*
# part is the EC2 Instance Connect push below — authorized for ~60s per
# connection — not the local key file. Reusing the key is what makes herdr's
# two near-simultaneous ssh connections (platform detection + the bridge) safe:
# if they both regenerated a shared key file they would race and leave the
# private key and its .pub from different generations, so ssh refuses to sign
# ("private key contents do not match public"). Generation is guarded by a
# portable mkdir lock (macOS has no flock) and only happens when the key is
# missing, so steady-state connections never regenerate and cannot race.
ensure_key() {
  [ -f "$key" ] && [ -f "$key.pub" ] && return 0
  local lock="$state/.keygen.lock" i age
  for i in $(seq 1 100); do
    if mkdir "$lock" 2>/dev/null; then
      if [ ! -f "$key" ] || [ ! -f "$key.pub" ]; then
        rm -f "$key" "$key.pub"
        ssh-keygen -t ed25519 -N '' -q -f "$key" -C "herdr-aws-ssm"
        chmod 600 "$key"
      fi
      rmdir "$lock" 2>/dev/null || true
      return 0
    fi
    # Steal a stale lock left by a crashed run (>10s old).
    if [ -d "$lock" ]; then
      age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0) ))
      [ "$age" -ge 10 ] && rmdir "$lock" 2>/dev/null || true
    fi
    [ -f "$key" ] && [ -f "$key.pub" ] && return 0
    sleep 0.1
  done
  [ -f "$key" ] && [ -f "$key.pub" ]
}
ensure_key || { hs_err "could not create SSH key in $state"; exit 1; }

az="$(aws ec2 describe-instances --instance-ids "$host" \
        --profile "$profile" --region "$region" \
        --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
        --output text)"
# Validate AZ: empty or "None" means wrong region/account or instance is gone.
case "${az:-}" in
  ''|None) hs_err "cannot resolve AZ for $host (wrong region/account or instance gone)"; exit 1 ;;
esac

push_cmd=(aws ec2-instance-connect send-ssh-public-key
  --instance-id "$host" --instance-os-user "$osuser"
  --availability-zone "$az" --ssh-public-key "file://$key.pub"
  --profile "$profile" --region "$region")

session_cmd=(aws ssm start-session --target "$host"
  --document-name AWS-StartSSHSession
  --parameters "portNumber=$port"
  --profile "$profile" --region "$region")

if [ "${HS_PROXY_PRINT:-}" = "1" ]; then
  printf '%s\n' "${push_cmd[*]}"   # display-only: elements joined with spaces, not for eval
  printf '%s\n' "${session_cmd[*]}" # display-only: elements joined with spaces, not for eval
  exit 0
fi

"${push_cmd[@]}" >/dev/null
exec "${session_cmd[@]}"
