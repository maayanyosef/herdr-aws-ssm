# shellcheck shell=bash
# Shared helpers for herdr-aws-ssm. Source, do not execute.
hs_log() { printf '%s\n' "$*" >&2; }
hs_err() { printf 'herdr-aws-ssm: %s\n' "$*" >&2; }

# Load configuration. Precedence (later overrides earlier):
#   1. built-in generic defaults (current AWS context)
#   2. $HERDR_PLUGIN_CONFIG_DIR/config.env  (installed-plugin user config)
#   3. $HERDR_PLUGIN_ROOT/.env              (local-dev overrides, git-ignored)
# No accounts or personal data are baked in; unset values fall back to the
# caller's AWS context ($AWS_PROFILE / $AWS_REGION) or common defaults.
hs_load_config() {
  if [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -f "$HERDR_PLUGIN_CONFIG_DIR/config.env" ]; then
    # shellcheck disable=SC1091
    source "$HERDR_PLUGIN_CONFIG_DIR/config.env"
  fi
  if [ -n "${HERDR_PLUGIN_ROOT:-}" ] && [ -f "$HERDR_PLUGIN_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    source "$HERDR_PLUGIN_ROOT/.env"
  fi
  : "${HERDR_SSM_REGION:=${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}}"
  : "${HERDR_SSM_OSUSER:=auto}"
  : "${HERDR_SSM_PROFILES:=default=${AWS_PROFILE:-default}}"
  export HERDR_SSM_REGION HERDR_SSM_OSUSER HERDR_SSM_PROFILES
}

# hs_envs and hs_profile_for_env require hs_load_config to have been called first
# (they iterate $HERDR_SSM_PROFILES which hs_load_config populates).
hs_envs() {
  local pair
  for pair in $HERDR_SSM_PROFILES; do printf '%s ' "${pair%%=*}"; done
}

hs_profile_for_env() {
  local want="$1" pair
  for pair in $HERDR_SSM_PROFILES; do
    if [ "${pair%%=*}" = "$want" ]; then printf '%s' "${pair#*=}"; return 0; fi
  done
  return 1
}

# Map an AMI's name/description/platform text to the conventional SSH login user.
# Input is any free text (e.g. "Name Description PlatformDetails"); matching is
# case-insensitive. Falls back to ec2-user (the most common AWS default).
hs_osuser_from_image_name() {
  local s
  s="$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]')"
  case "$s" in
    *ubuntu*)                 printf 'ubuntu' ;;
    *debian*)                 printf 'admin' ;;
    *centos*)                 printf 'centos' ;;
    *fedora*)                 printf 'fedora' ;;
    *bitnami*)                printf 'bitnami' ;;
    *amzn*|*"amazon linux"*)  printf 'ec2-user' ;;
    *rhel*|*"red hat"*)       printf 'ec2-user' ;;
    *suse*|*sles*)            printf 'ec2-user' ;;
    *)                        printf 'ec2-user' ;;
  esac
}

hs_pick() {
  local prompt="${1:-select}"
  local lines=() line
  while IFS= read -r line; do lines+=("$line"); done
  [ "${#lines[@]}" -gt 0 ] || return 1

  if [ -z "${HS_PICK_INDEX:-}" ] && command -v fzf >/dev/null 2>&1 && [ -t 0 ]; then
    printf '%s\n' "${lines[@]}" | fzf --prompt="$prompt> " --height=40% --reverse
    return $?
  fi

  local i idx
  for i in "${!lines[@]}"; do printf '%3d) %s\n' "$((i+1))" "${lines[$i]}" >&2; done
  if [ -n "${HS_PICK_INDEX:-}" ]; then
    idx="$HS_PICK_INDEX"
  else
    printf '%s [1-%d]: ' "$prompt" "${#lines[@]}" >&2
    read -r idx < /dev/tty
  fi
  case "$idx" in (''|*[!0-9]*) return 1 ;; esac
  [ "$idx" -ge 1 ] && [ "$idx" -le "${#lines[@]}" ] || return 1
  printf '%s\n' "${lines[$((idx-1))]}"
}
