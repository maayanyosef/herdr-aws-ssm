# herdr-aws-ssm

Connect to EC2 instances over **AWS SSM Session Manager** from
[herdr](https://herdr.dev), using `herdr --remote` for the full thin-client
(remote herdr install, clipboard bridge, persistent session). SSH auth uses
short-lived keys pushed via EC2 Instance Connect — no persistent keys on hosts.

Works with any AWS account: it uses your current AWS CLI profiles/region, and
auto-detects the SSH login user from each instance's AMI.

## How it works

1. `setup` writes an `~/.ssh/config` block routing `Host i-* mi-*` through
   `bin/proxy.sh`, which pushes an ephemeral public key
   (`ec2-instance-connect send-ssh-public-key`) and opens an SSM SSH session
   (`AWS-StartSSHSession`). After this, `herdr --remote i-…` tunnels over SSM.
2. `connect` lists running instances across your configured profiles, lets you
   pick one (fzf or a numbered menu), detects the right SSH user from the
   instance's AMI, confirms production targets, and runs
   `herdr --remote <user>@<instance>`.

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

## Install

```bash
herdr plugin install maayanyosef/herdr-aws-ssm

# or, for local development:
git clone https://github.com/maayanyosef/herdr-aws-ssm && cd herdr-aws-ssm
herdr plugin link .
```

Then run the **"SSM: install ssh config"** action once (it writes the
`~/.ssh/config` block) and **"SSM: doctor / preflight"** to verify your
toolchain and credentials. After that, run **"SSM connect (herdr --remote)"** to
pick an instance and connect.

## Keybinding (optional)

This plugin does not claim a default key. To bind the connect action, add to
your herdr `config.toml`:

```toml
[[keys.command]]
key = "prefix+e"            # pick any free combo
type = "plugin_action"
command = "herdr-aws-ssm.connect"
description = "SSM connect to an EC2 instance"
```

## Configuration

All settings are optional. Unset values fall back to your current AWS context
(`$AWS_PROFILE` / `$AWS_REGION`) and sensible defaults — so it works with no
configuration at all.

| Var                  | Default                                             | Meaning                                     |
|----------------------|-----------------------------------------------------|---------------------------------------------|
| `HERDR_SSM_PROFILES` | `default=$AWS_PROFILE` (or `default`)               | Space-separated `env=aws-profile` pairs     |
| `HERDR_SSM_REGION`   | `$AWS_REGION` → `$AWS_DEFAULT_REGION` → `us-east-1` | AWS region to search/connect in             |
| `HERDR_SSM_OSUSER`   | `auto`                                              | SSH login user; `auto` detects from the AMI |

- **`HERDR_SSM_PROFILES`** — each `env` label is arbitrary. Any label named
  exactly `prod` is treated as production and requires a typed `yes-prod`
  confirmation before connecting.
- **`HERDR_SSM_OSUSER=auto`** maps the instance's AMI to a login user
  (Ubuntu → `ubuntu`, Amazon Linux → `ec2-user`, Debian → `admin`, …), falling
  back to `ec2-user`. Set a fixed value to skip detection.

Set these two ways:

- **Local development:** copy `.env.example` to `.env` (git-ignored) and edit.
- **Installed plugin:** `setup` writes a `config.env` into the plugin's config
  dir; edit it there.

## Tests

```bash
for t in tests/*_test.sh; do bash "$t" || exit 1; done
```

## License

MIT — see [LICENSE](LICENSE).
