#!/usr/bin/env bash
set -euo pipefail
HS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HS_DIR/lib/common.sh"
hs_load_config

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

region="$HERDR_SSM_REGION"

# Gather SSM ping status across all profiles as "id<TAB>status" lines (bash 3.2
# safe — no associative arrays, since herdr may invoke macOS /bin/bash 3.2).
ping_data=""
for env in $(hs_envs); do
  profile="$(hs_profile_for_env "$env")"
  ssm_out="$(aws ssm describe-instance-information --profile "$profile" --region "$region" \
               --query 'InstanceInformationList[].[InstanceId,PingStatus]' --output text 2>/dev/null)" || \
    hs_err "SSM status unavailable for $env (try: aws sso login --profile $profile)"
  ping_data+="$ssm_out"$'\n'
done
ping_status() {  # $1=instance-id -> Online|ConnectionLost|... or "unknown"
  printf '%s\n' "$ping_data" | awk -v id="$1" '$1==id{print $2; f=1; exit} END{if(!f)print "unknown"}'
}

# Build candidate rows: "env|id|display"
rows=()
for env in $(hs_envs); do
  profile="$(hs_profile_for_env "$env")"
  while IFS=$'\t' read -r id itype az name; do
    [ -n "$id" ] || continue
    [ "$name" = "None" ] && name="(no-name)"
    local_ssm="$(ping_status "$id")"
    flag=""; [ "$env" = "prod" ] && flag=" !PROD"
    display="$(printf '[%s] %-22s %-19s %-12s %-9s ssm:%s%s' \
                "$env" "$name" "$id" "$itype" "$az" "$local_ssm" "$flag")"
    rows+=("$env|$id|$display")
  done < <(aws ec2 describe-instances --profile "$profile" --region "$region" \
             --filters Name=instance-state-name,Values=running \
             --query "Reservations[].Instances[].[InstanceId,InstanceType,Placement.AvailabilityZone,Tags[?Key=='Name']|[0].Value]" \
             --output text 2>/dev/null)
done

[ "${#rows[@]}" -gt 0 ] || { hs_err "no running instances found"; exit 1; }

# Pick by display text, then map back to env|id.
displays=()
for r in "${rows[@]}"; do displays+=("${r#*|*|}"); done
chosen_display="$(printf '%s\n' "${displays[@]}" | hs_pick 'instance')" || { hs_err "no selection"; exit 1; }

env=""; id=""
for r in "${rows[@]}"; do
  if [ "${r#*|*|}" = "$chosen_display" ]; then env="${r%%|*}"; rest="${r#*|}"; id="${rest%%|*}"; break; fi
done
[ -n "$id" ] || { hs_err "selection not resolved"; exit 1; }
profile="$(hs_profile_for_env "$env")"

# Prod guard.
if [ "$env" = "prod" ]; then
  if [ -n "${HS_CONFIRM:-}" ]; then ans="$HS_CONFIRM"
  else printf 'PROD target %s. Type yes-prod to continue: ' "$id" >&2; read -r ans < /dev/tty; fi
  [ "$ans" = "yes-prod" ] || { hs_err "prod connection aborted"; exit 1; }
fi

# Resolve the SSH login user. When HERDR_SSM_OSUSER=auto, detect it from the
# instance's AMI (Ubuntu->ubuntu, Amazon Linux->ec2-user, ...). The user is
# passed in the herdr target (user@id) so ssh's login user and the EIC key push
# in proxy.sh (which honors %r) always agree.
osuser="$HERDR_SSM_OSUSER"
if [ "$osuser" = "auto" ]; then
  ami="$(aws ec2 describe-instances --instance-ids "$id" --profile "$profile" --region "$region" \
           --query 'Reservations[0].Instances[0].ImageId' --output text 2>/dev/null || true)"
  imgtext=""
  if [ -n "$ami" ] && [ "$ami" != "None" ]; then
    imgtext="$(aws ec2 describe-images --image-ids "$ami" --profile "$profile" --region "$region" \
                 --query 'Images[0].[Name,Description,PlatformDetails]' --output text 2>/dev/null || true)"
  fi
  osuser="$(hs_osuser_from_image_name "$imgtext")"
fi

export HERDR_SSM_PROFILE="$profile" HERDR_SSM_REGION="$region"
# osuser reaches proxy.sh as the ssh remote-user (%r) via the target below.

if [ "$dry_run" -eq 1 ]; then
  printf 'WOULD: herdr --remote %s@%s (profile=%s)\n' "$osuser" "$id" "$profile"
  exit 0
fi
exec herdr --remote "$osuser@$id"
