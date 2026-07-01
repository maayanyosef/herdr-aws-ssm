#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/assert.sh"
source "$ROOT/lib/common.sh"

# Neutralize the ambient AWS context so default assertions are deterministic
# regardless of the developer's shell.
clear_aws_env() {
  unset HERDR_SSM_REGION HERDR_SSM_OSUSER HERDR_SSM_PROFILES \
        HERDR_PLUGIN_CONFIG_DIR HERDR_PLUGIN_ROOT \
        AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION
}

test_defaults_applied() {
  clear_aws_env
  hs_load_config
  assert_eq "us-east-1" "$HERDR_SSM_REGION" region || return 1
  assert_eq "auto" "$HERDR_SSM_OSUSER" osuser || return 1
  assert_eq "default=default" "$HERDR_SSM_PROFILES" profiles || return 1
}

test_default_profile_follows_aws_profile() {
  clear_aws_env
  AWS_PROFILE="my-sso"
  hs_load_config
  assert_eq "default=my-sso" "$HERDR_SSM_PROFILES" from-aws-profile || return 1
}

test_profile_lookup() {
  clear_aws_env
  HERDR_SSM_PROFILES="dev=acct-dev prod=acct-prod"
  hs_load_config
  assert_eq "acct-dev" "$(hs_profile_for_env dev)" dev || return 1
  assert_eq "acct-prod" "$(hs_profile_for_env prod)" prod || return 1
}

test_unknown_env_fails() {
  clear_aws_env
  HERDR_SSM_PROFILES="dev=acct-dev"
  hs_load_config
  if hs_profile_for_env nope >/dev/null 2>&1; then return 1; fi
}

test_config_file_overrides() {
  clear_aws_env
  local cfg_dir; cfg_dir="$(mktemp -d)"
  HERDR_PLUGIN_CONFIG_DIR="$cfg_dir"
  printf 'HERDR_SSM_OSUSER=ubuntu\n' > "$cfg_dir/config.env"
  hs_load_config
  assert_eq "ubuntu" "$HERDR_SSM_OSUSER" config-override || return 1
}

test_env_file_overrides() {
  clear_aws_env
  local root; root="$(mktemp -d)"
  HERDR_PLUGIN_ROOT="$root"
  printf 'HERDR_SSM_REGION=eu-west-1\n' > "$root/.env"
  hs_load_config
  assert_eq "eu-west-1" "$HERDR_SSM_REGION" env-override || return 1
}

test_envs_listed() {
  clear_aws_env
  HERDR_SSM_PROFILES="dev=acct-dev prod=acct-prod"
  hs_load_config
  local envs; envs="$(hs_envs)"
  assert_contains "$envs" "dev" envs-dev || return 1
  assert_contains "$envs" "prod" envs-prod || return 1
}

test_osuser_from_image() {
  assert_eq "ubuntu"   "$(hs_osuser_from_image_name 'ubuntu/images/hvm-ssd/ubuntu-jammy-22.04')" ubuntu || return 1
  assert_eq "ec2-user" "$(hs_osuser_from_image_name 'amzn2-ami-hvm-2.0 Amazon Linux 2')" amzn || return 1
  assert_eq "ec2-user" "$(hs_osuser_from_image_name 'RHEL-9.0 Red Hat')" rhel || return 1
  assert_eq "admin"    "$(hs_osuser_from_image_name 'debian-12-amd64')" debian || return 1
  assert_eq "ec2-user" "$(hs_osuser_from_image_name 'some-unknown-image')" fallback || return 1
}

run_tests
