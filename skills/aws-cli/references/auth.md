# AWS CLI Auth Reference

## Credential precedence (highest first)

1. CLI flags (`--profile`)
2. Env vars: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`, `AWS_REGION`
3. `~/.aws/credentials` + `~/.aws/config`
4. Container creds (ECS task role)
5. EC2 instance metadata (IMDSv2)

## SSO (most common modern setup)

```bash
# one-time per profile in ~/.aws/config
aws configure sso

# refresh token (interactive browser)
aws sso login --profile <name>

# inspect cached session
aws sso list-accounts --profile <name>
```

Token lives in `~/.aws/sso/cache/`. Expires per session policy (often 8–12h).

## Static keys (legacy)

```bash
aws configure --profile <name>
# prompts for key, secret, region, output format
```

Stored in `~/.aws/credentials`. Avoid for shared / CI work — use IAM Identity Center, OIDC, or instance roles.

## Assume role

```bash
# in ~/.aws/config
[profile prod]
role_arn = arn:aws:iam::123456789012:role/Admin
source_profile = default
region = us-east-1

# or one-shot
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/Admin \
  --role-session-name claude-session
```

## Diagnose auth failures

```bash
aws configure list                   # see resolved profile + cred source
aws sts get-caller-identity          # whoami
aws sts get-caller-identity --debug  # full request log
echo $AWS_PROFILE $AWS_REGION        # env override?
ls -la ~/.aws/                       # config files exist?
```

## Common errors

- **`Unable to locate credentials`** — no source resolved. Set `AWS_PROFILE` or run `aws configure`.
- **`The security token included in the request is expired`** — `aws sso login --profile <name>` or rotate keys.
- **`The config profile (X) could not be found`** — typo or missing `[profile X]` block in `~/.aws/config`.
- **`AccessDenied: ... is not authorized to perform: sts:AssumeRole`** — IAM trust policy missing your principal.
