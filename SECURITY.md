# Security

`herdr-aws-ssm` is a thin **Bash orchestration layer** over the AWS CLI, the
Session Manager plugin, and `ssh`. It runs as you, with your AWS credentials —
like any herdr plugin, it is **not sandboxed**. Its security posture is about
handling your credentials and the connection safely, and not leaking anything
into the repo.

## Threat model & mitigations

- **No long-lived authorization.** Authentication uses **EC2 Instance Connect**:
  on every connection `bin/proxy.sh` pushes an SSH public key with
  `ec2-instance-connect send-ssh-public-key` (authorized for ~60s) and opens the
  SSM SSH session immediately. Nothing is added to the instance's
  `authorized_keys`; the pushed authorization expires on its own. The local
  `ed25519` keypair is generated once (`0600` key in a `chmod 700` state dir)
  and reused across connections — only its short-lived *push* grants access — and
  it is never printed or logged.

- **No secrets in the repo.** Credentials are never read from or written to the
  repository. Configuration holds only AWS profile *names* and a region — no
  keys. `.env` (local config) is git-ignored; a `tests/release_test.sh` check
  scans tracked files for AWS access keys, private-key blocks, SSO/account
  identifiers, and the maintainer's name, and fails the build if any appear.

- **Discovery is read-only.** `connect`/`doctor` call only read-only AWS APIs
  (`sts get-caller-identity`, `ec2 describe-instances`, `ec2 describe-images`,
  `ssm describe-instance-information`). The plugin never creates, modifies, or
  deletes AWS resources. The only state-changing calls are the transient
  ephemeral-key push and opening an SSM session — both required to connect, both
  scoped to a single instance you selected.

- **Production guardrail.** Any profile whose env label is exactly `prod` is
  flagged in the picker and requires a typed `yes-prod` confirmation before
  connecting. The gate fails **closed**: with no confirmation and no TTY, the
  connection aborts rather than proceeding.

- **Login user matches the pushed key.** The connect action detects the SSH user
  from the instance's AMI and passes it in the target (`user@id`) so the user
  `ssh` logs in as is exactly the user the ephemeral key was pushed for — a
  mismatch can't silently authorize the wrong account.

- **Argument hygiene.** Instance ids, profiles, region, and os-user flow to `aws`
  and `ssh` as ordinary argv arguments (no `eval`, no shell interpolation of
  file contents). The resolved availability zone is validated (empty/`None`
  aborts with a clear error) so a stale/foreign instance id fails fast instead
  of producing a confusing AWS error.

- **Safe ssh-config edits.** `setup` writes a clearly delimited managed block to
  `~/.ssh/config` **atomically** (temp file + `mv`, `0600`), preserving all other
  content and never duplicating the block on re-run — an interrupted run can't
  truncate your ssh config. New host keys are accepted on first use
  (`StrictHostKeyChecking accept-new`); the SSM channel itself is authenticated
  by AWS IAM.

## Trust

Like every herdr plugin, this one executes with your privileges and AWS
credentials and is not reviewed or sandboxed by herdr. Install it only from a
source you trust, and read the scripts — they are short, dependency-free Bash.

## Reporting a vulnerability

Please report suspected vulnerabilities privately rather than opening a public
issue: open a **GitHub private security advisory** ("Security" → "Report a
vulnerability") on this repository. You'll get an acknowledgement and a fix or
mitigation plan once the report is triaged. Thank you for helping keep it safe.
