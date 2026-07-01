#!/usr/bin/env bash
set -uo pipefail
HS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HS_DIR/lib/common.sh"
hs_load_config

fail=0
check_hard() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok    %s\n' "$1"
  else
    printf 'MISS  %s  (%s)\n' "$1" "$2"; fail=1
  fi
}
check_soft() {
  if command -v "$1" >/dev/null 2>&1; then printf 'ok    %s\n' "$1"
  else printf 'warn  %s  (%s)\n' "$1" "$2"; fi
}

check_hard aws "install AWS CLI v2"
check_hard session-manager-plugin "install the AWS Session Manager plugin"
check_hard herdr "install herdr"
check_soft fzf "optional: enables fuzzy picker (numbered menu used otherwise)"

if [ "${HS_DOCTOR_SKIP_AWS:-}" != "1" ]; then
  for env in $(hs_envs); do
    profile="$(hs_profile_for_env "$env")"
    if aws sts get-caller-identity --profile "$profile" --region "$HERDR_SSM_REGION" >/dev/null 2>&1; then
      printf 'ok    sso %s (%s)\n' "$env" "$profile"
    else
      printf 'warn  sso %s: run  aws sso login --profile %s\n' "$env" "$profile"
    fi
  done
fi

[ "$fail" -eq 0 ] || { hs_err "missing required dependencies"; exit 1; }
echo "doctor: ok"
