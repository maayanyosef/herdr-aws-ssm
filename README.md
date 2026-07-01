# herdr-aws-ssm

[![CI](https://github.com/maayanyosef/herdr-aws-ssm/actions/workflows/ci.yaml/badge.svg)](https://github.com/maayanyosef/herdr-aws-ssm/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Bash 3.2+](https://img.shields.io/badge/bash-3.2%2B-4EAA25.svg)
![herdr 0.7+](https://img.shields.io/badge/herdr-0.7%2B-8a2be2)
![platforms: linux • macOS](https://img.shields.io/badge/platforms-linux%20%E2%80%A2%20macOS-informational)

**Connect to your EC2 instances over AWS SSM without leaving your terminal — pick
an instance from a fuzzy list and drop into a full [herdr](https://herdr.dev)
`--remote` session, tunneled through Session Manager.** No bastion, no public IP,
no long-lived SSH keys: authentication uses short-lived EC2 Instance Connect keys,
and the right SSH user is detected from each instance's AMI. Works with any AWS
account using your existing CLI profiles.

## Why you'd want it

- **`herdr --remote`, over SSM.** You get herdr's full thin client — remote herdr
  install, clipboard bridge, persistent session that survives detach/reattach —
  but the transport is an SSM `AWS-StartSSHSession` tunnel instead of a reachable
  SSH endpoint. Private-subnet boxes with no inbound work fine.
- **No keys to manage.** Each connection pushes an ephemeral EC2 Instance Connect
  key (~60s), then opens the session. Nothing persists on the instance, nothing
  sits in your repo.
- **The right user, automatically.** Ubuntu → `ubuntu`, Amazon Linux → `ec2-user`,
  Debian → `admin`, … detected from the instance's AMI so you don't have to
  remember per-image logins.
- **Safe with production.** Any profile you label `prod` is flagged in the picker
  and requires a typed `yes-prod` before it connects — the gate fails closed.
- **Zero config to start.** Uses your current AWS profile/region out of the box;
  point it at more accounts when you want. Pure Bash, no build step,
  [hardened](SECURITY.md) around your credentials.

## What it does

- **Discover across accounts** — lists running instances for every profile you
  configure (Name tag, id, type, AZ), and marks each with its SSM reachability
  (`ssm:Online`) so you don't pick a target the agent can't reach.
- **Pick fast** — a fuzzy picker (`fzf` if installed, a numbered menu otherwise);
  `prod`-labelled targets are flagged and gated behind a typed confirmation.
- **Detect the SSH user** — resolves the login user from the picked instance's
  AMI and connects as `herdr --remote <user>@<id>`, so the login user always
  matches the ephemeral key that was pushed.
- **Install the transport once** — writes a managed `~/.ssh/config` block that
  routes `Host i-* mi-*` through the SSM ProxyCommand, atomically and
  idempotently; after that even a bare `herdr --remote i-…` tunnels over SSM.
- **Check your setup** — `doctor` verifies the AWS CLI, Session Manager plugin,
  `herdr`, and that each profile's credentials are live.

## Quick start

```bash
# 1. Install the plugin (replace <owner> with the account hosting this repo):
herdr plugin install <owner>/herdr-aws-ssm

# 2. Make sure the AWS CLI v2 + Session Manager plugin are installed (see below),
#    and that a profile is authenticated:
aws sso login --profile my-profile      # or any credential source

# 3. Install the ssh-config transport once, then check everything:
#    run the "SSM: install ssh config" and "SSM: doctor / preflight" actions.
```

Then **bind a key** in your herdr config (`~/.config/herdr/config.toml`) so one
press opens the picker:

```toml
[[keys.command]]
key = "prefix+e"            # pick any free combo
type = "plugin_action"
command = "herdr-aws-ssm.connect"
description = "SSM connect to an EC2 instance"
```

Run `herdr server reload-config`, then press your key, pick an instance, and
you're in. (No keybinding is forced by the plugin — it would risk colliding with
a herdr built-in.)

## Actions

| Action | id | What it does |
| --- | --- | --- |
| **SSM connect (herdr --remote)** | `connect` | List instances → pick → detect user → confirm prod → `herdr --remote <user>@<id>` |
| **SSM: install ssh config** | `setup` | Write the managed `~/.ssh/config` block + a starter config; run once |
| **SSM: doctor / preflight** | `doctor` | Verify AWS CLI, `session-manager-plugin`, `herdr`, and live credentials per profile |

## How it works

1. **`setup`** writes an `~/.ssh/config` block routing `Host i-* mi-*` through
   `bin/proxy.sh`. The write is atomic (temp file + `mv`) and idempotent (a
   delimited managed block), so it never duplicates or truncates your config.
2. **`bin/proxy.sh`** (the ssh `ProxyCommand`) pushes an ephemeral public key with
   `ec2-instance-connect send-ssh-public-key`, then execs
   `aws ssm start-session --document-name AWS-StartSSHSession`. ssh runs its
   handshake over that SSM channel.
3. **`connect`** lists instances across your profiles, lets you pick one, detects
   the SSH user from its AMI, gates production, and launches
   `herdr --remote <user>@<id>` — so ssh's login user and the pushed key agree.

## Prerequisites

- AWS CLI v2 + `session-manager-plugin` (see below); `fzf` optional (numbered
  menu otherwise).
- An authenticated AWS profile (`aws sso login --profile <p>`, or any credential
  source the AWS CLI understands).
- Instances: SSM agent running + an instance profile with
  `AmazonSSMManagedInstanceCore`.
- IAM: `ssm:StartSession` (with the `AWS-StartSSHSession` document) and
  `ec2-instance-connect:SendSSHPublicKey`.

### Installing the AWS CLI

AWS CLI v2 install instructions (all platforms):
<https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html>

```bash
# macOS (Homebrew)
brew install awscli
```

Verify with `aws --version` (expect `aws-cli/2.x`).

### Installing the Session Manager plugin

`aws ssm start-session` needs the Session Manager plugin installed locally. Full
per-OS instructions:
<https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html>

```bash
# macOS (Homebrew)
brew install --cask session-manager-plugin

# Debian / Ubuntu (x86_64)
curl -o /tmp/session-manager-plugin.deb \
  "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
sudo dpkg -i /tmp/session-manager-plugin.deb

# RHEL / Amazon Linux (x86_64)
sudo dnf install -y \
  "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm"
```

Verify with `session-manager-plugin --version`. `doctor` also checks for it.

## Configuration

All settings are optional. Unset values fall back to your current AWS context
(`$AWS_PROFILE` / `$AWS_REGION`) and sensible defaults — so it works with no
configuration at all.

| Var                  | Default                                             | Meaning                                     |
|----------------------|-----------------------------------------------------|---------------------------------------------|
| `HERDR_SSM_PROFILES` | `default=$AWS_PROFILE` (or `default`)               | Space-separated `env=aws-profile` pairs     |
| `HERDR_SSM_REGION`   | `$AWS_REGION` → `$AWS_DEFAULT_REGION` → `us-east-1`  | AWS region to search/connect in            |
| `HERDR_SSM_OSUSER`   | `auto`                                              | SSH login user; `auto` detects from the AMI |

- **`HERDR_SSM_PROFILES`** — each `env` label is arbitrary. Any label named
  exactly `prod` is treated as production and requires a typed `yes-prod`
  confirmation before connecting. Example:
  `HERDR_SSM_PROFILES="dev=my-dev-sso prod=my-prod-sso"`.
- **`HERDR_SSM_OSUSER=auto`** maps the instance's AMI to a login user
  (Ubuntu → `ubuntu`, Amazon Linux → `ec2-user`, Debian → `admin`, …), falling
  back to `ec2-user`. Set a fixed value to skip detection.

Set these two ways:

- **Local development:** copy `.env.example` to `.env` (git-ignored) and edit.
- **Installed plugin:** `setup` writes a `config.env` into the plugin's config
  dir; edit it there.

## Security

The plugin runs as you, with your AWS credentials, and is not sandboxed. It uses
ephemeral keys, keeps no secrets in the repo, only calls read-only AWS APIs for
discovery, and gates production. See **[SECURITY.md](SECURITY.md)** for the full
threat model and how to report a vulnerability.

## Development

Pure Bash, no build step. The test suite uses a tiny in-repo harness (no `bats`)
and stubs `aws`/`herdr` on `PATH`, so it needs no AWS access:

```bash
for t in tests/*_test.sh; do bash "$t" || exit 1; done
```

CI runs the suite on Linux (bash 5) and macOS (bash 3.2, the compatibility floor)
and lints with `shellcheck`. Releases are cut by pushing a `vX.Y.Z` tag matching
`herdr-plugin.toml` (see `.github/workflows/`).

## License

[MIT](LICENSE) © herdr-aws-ssm contributors
