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

# Ephemeral keypair: regenerate if missing or older than ~50s.
# Guard age >= 0 to handle clock skew (future mtime would yield negative age,
# which would be treated as permanently fresh and cause SSM's key window to expire).
needs_key=1
if [ -f "$key" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$key" 2>/dev/null || stat -c %Y "$key") ))
  [ "$age" -ge 0 ] && [ "$age" -lt 50 ] && needs_key=0
fi
if [ "$needs_key" -eq 1 ]; then
  rm -f "$key" "$key.pub"
  ssh-keygen -t ed25519 -N '' -q -f "$key" -C "herdr-aws-ssm-ephemeral"
  chmod 600 "$key"
fi

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
