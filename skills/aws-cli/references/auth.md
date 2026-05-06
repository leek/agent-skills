# AWS CLI Auth Reference

## Selecting a profile

`--profile <name>` flag and `AWS_PROFILE=<name>` env var are **equivalent** — both pick a named profile from `~/.aws/config` / `~/.aws/credentials`.

```bash
# flag form — scoped to one command
aws s3 ls --profile production

# env form — sticks for the shell session
export AWS_PROFILE=production
aws s3 ls

# one-shot env (no export)
AWS_PROFILE=production aws s3 ls
```

If both are set, the **flag wins**. If neither is set, the profile named `default` is used.

The `--profile` flag works on every `aws` subcommand.

## Credential precedence (highest first)

1. **CLI flags** — `--profile`, explicit per-command credentials
2. **Env vars** — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`, `AWS_REGION`
3. **Web identity token** (EKS IRSA, GitHub Actions OIDC) — `AWS_WEB_IDENTITY_TOKEN_FILE` + `AWS_ROLE_ARN`
4. **SSO** — cached SSO token resolved via `~/.aws/config` profile
5. **Shared credentials file** — `~/.aws/credentials`
6. **`credential_process`** in `~/.aws/config` — external helper (aws-vault, 1Password, vault)
7. **Container creds** — ECS task role (`AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`)
8. **Instance metadata** — EC2 instance profile (IMDSv2)

First match wins.

## `~/.aws/credentials` and `~/.aws/config`

Two files. Different syntax for the default profile — common gotcha.

**`~/.aws/credentials`** — long-lived keys only. Section names are bare profile names:

```ini
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

[production]
aws_access_key_id = AKIAI44QH8DHBEXAMPLE
aws_secret_access_key = je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
```

**`~/.aws/config`** — settings, role chains, SSO. Default uses `[default]`, **everything else uses `[profile X]`**:

```ini
[default]
region = us-west-2
output = json

[profile production]
region = us-east-1
output = text

[profile cross-account]
role_arn = arn:aws:iam::123456789012:role/Admin
source_profile = default
role_session_name = claude-session
duration_seconds = 3600

[profile mfa]
role_arn = arn:aws:iam::123456789012:role/MFARole
source_profile = default
mfa_serial = arn:aws:iam::111111111111:mfa/myuser
```

The asymmetry (`[default]` vs `[profile X]`) is the single most common config mistake. `[production]` in `~/.aws/config` will **not** be found — must be `[profile production]`.

File permissions should be `600`. AWS CLI warns on looser perms.

Override file paths with `AWS_CONFIG_FILE` / `AWS_SHARED_CREDENTIALS_FILE`.

## SSO (modern setup)

Recommended over static keys. Two block styles — newer one (since CLI v2.9) uses a shared SSO session:

```ini
[sso-session my-org]
sso_start_url = https://my-org.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile dev]
sso_session = my-org
sso_account_id = 111111111111
sso_role_name = PowerUserAccess
region = us-east-1

[profile prod]
sso_session = my-org
sso_account_id = 222222222222
sso_role_name = ReadOnlyAccess
region = us-east-1
```

Commands:

```bash
aws configure sso              # interactive setup, writes config blocks
aws sso login --profile dev    # browser flow, caches token
aws sso login --sso-session my-org   # refresh all profiles using this session
aws sso logout                 # clear cached token
rm -rf ~/.aws/sso/cache/*      # nuke cache if `logout` misbehaves
```

Token lives in `~/.aws/sso/cache/`. Expires per session policy (typically 8–12h).

## Static keys (legacy)

```bash
aws configure --profile <name>
# prompts: key, secret, region, output format
# writes to ~/.aws/credentials and ~/.aws/config
```

Avoid for shared / CI work — use IAM Identity Center, GitHub OIDC, or instance roles. Rotate every 90 days if you must keep them.

## Assume role

Profile-based (preferred — CLI auto-refreshes):

```ini
# ~/.aws/config
[profile admin]
role_arn = arn:aws:iam::123456789012:role/Admin
source_profile = default
region = us-east-1
```

```bash
aws s3 ls --profile admin   # CLI calls sts:AssumeRole transparently
```

One-shot:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/Admin \
  --role-session-name claude-session \
  --duration-seconds 3600

# returns Credentials.{AccessKeyId,SecretAccessKey,SessionToken}
# export those as AWS_* env vars to use them
```

With MFA (one-shot):

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/Admin \
  --role-session-name claude-session \
  --serial-number arn:aws:iam::111111111111:mfa/myuser \
  --token-code 123456
```

With MFA (profile-based — CLI prompts for code):

```ini
[profile mfa]
role_arn = arn:aws:iam::123456789012:role/Admin
source_profile = default
mfa_serial = arn:aws:iam::111111111111:mfa/myuser
```

## `credential_process` (external helper)

Delegates credential resolution to an external command. Good for vaulted keys (aws-vault, 1Password, HashiCorp Vault).

```ini
[profile vault]
credential_process = aws-vault export --json --no-session production
region = us-east-1
```

The command must print JSON to stdout:

```json
{
  "Version": 1,
  "AccessKeyId": "...",
  "SecretAccessKey": "...",
  "SessionToken": "...",
  "Expiration": "2026-01-01T00:00:00Z"
}
```

CLI caches by `Expiration`. No keys ever land in `~/.aws/credentials`.

## Web identity token (OIDC)

For EKS pods (IRSA) and GitHub Actions OIDC. Set by the runtime — usually no manual config:

```bash
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/PodRole
AWS_ROLE_SESSION_NAME=pod-session   # optional
```

CLI auto-resolves via `sts:AssumeRoleWithWebIdentity`.

## Diagnose auth failures

```bash
aws configure list                            # resolved profile + cred source
aws configure list --profile <name>           # one profile
aws configure list-profiles                   # all profiles
aws sts get-caller-identity                   # whoami
aws sts get-caller-identity --debug 2>&1 | tail -50   # full request log
env | grep AWS_                               # env overrides
ls -la ~/.aws/                                # files + perms
```

## Common errors

- **`Unable to locate credentials`** — no source resolved. Set `AWS_PROFILE` or run `aws configure` / `aws sso login`.
- **`The security token included in the request is expired`** — `aws sso login --profile <name>` or rotate keys.
- **`The config profile (X) could not be found`** — typo, **or** missing `profile` keyword: must be `[profile X]` not `[X]` in `~/.aws/config`.
- **`AccessDenied: ... is not authorized to perform: sts:AssumeRole`** — IAM trust policy on the target role doesn't list your principal.
- **`SignatureDoesNotMatch`** — clock skew. Run `date`, sync NTP.
- **`InvalidClientTokenId`** — wrong/revoked access key. Check `aws configure list` shows the right source.
