---
name: aws-cli
description: Use when running AWS CLI commands (`aws ...`) for any service — S3, EC2, IAM, Lambda, CloudFormation, Logs, RDS, ECS, etc. Triggers on phrases like "list s3 buckets", "describe ec2 instances", "check IAM role", "deploy lambda", "tail cloudwatch logs", "what AWS account am I in", or any direct invocation of the `aws` CLI. Enforces auth/identity verification, scoped queries, safe destructive ops, and JMESPath output filtering.
---

# AWS CLI

Run AWS CLI commands safely and efficiently. Default to **read-only** operations. Always confirm identity, region, and blast radius before mutating anything.

## Always Do First

Before any AWS CLI command, confirm three things:

1. **Identity** — `aws sts get-caller-identity` (account, principal)
2. **Region** — explicit `--region <r>` or `AWS_REGION` env. Do not rely on default profile region for cross-account work.
3. **Profile** — `AWS_PROFILE=<name>` if multiple. Show user which profile is active.

If `aws sts get-caller-identity` fails: stop. Do not retry blindly. Diagnose: missing creds, expired SSO session, wrong profile. See [references/auth.md](./references/auth.md).

## Output Filtering

The CLI returns large JSON. **Always** narrow output with `--query` (JMESPath) and `--output`.

```bash
# bad — dumps everything
aws ec2 describe-instances

# good — only what you need
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Type:InstanceType,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table
```

Common patterns: see [references/jmespath.md](./references/jmespath.md).

Prefer `--output table` for human review, `--output json` for piping to `jq`, `--output text` for shell loops.

## Pagination

Default CLI auto-paginates and may hang on huge result sets. For exploration:

- `--max-items 50` to cap
- `--no-paginate` for raw single page (then use `NextToken` if needed)
- `--page-size 100` to tune API call size

## Destructive Operations

Stop and confirm with the user before any of:

- `delete-*`, `terminate-*`, `destroy-*`, `remove-*`
- `put-*` / `create-*` that overwrites existing resources
- `update-*` on IAM, security groups, or KMS
- Anything against `prod` accounts/profiles
- `aws s3 rm --recursive`, `aws s3 sync --delete`

For destructive ops: prefer `--dry-run` first when supported. Show the exact resource ARN(s) that will be affected. Wait for explicit user confirmation.

## Region & Profile Hygiene

```bash
# inspect current context
aws configure list                   # shows profile, region, key source
aws configure list-profiles          # all named profiles
aws sts get-caller-identity          # who am I

# scope a single command without changing env
AWS_PROFILE=staging AWS_REGION=us-west-2 aws s3 ls
```

When user mentions a service in a region (e.g., "EU buckets"), pass `--region` explicitly — do not assume.

## Common Service Cheatsheet

Quick references kept short. Open the per-service file for details.

- **S3** — see [references/s3.md](./references/s3.md)
- **EC2** — see [references/ec2.md](./references/ec2.md)
- **IAM** — see [references/iam.md](./references/iam.md)
- **Lambda** — see [references/lambda.md](./references/lambda.md)
- **CloudWatch Logs** — see [references/logs.md](./references/logs.md)

## Errors

- `Unable to locate credentials` — no profile / env vars. Run `aws configure` or `aws sso login --profile <name>`.
- `ExpiredToken` / `Token has expired` — refresh: `aws sso login` or rotate keys.
- `AccessDenied` — show full error, identify principal + action + resource. Do **not** retry with broader perms; report to user.
- `ThrottlingException` — back off, add `--cli-read-timeout` or retry with jitter. Don't tight-loop.
- `RequestExpired` — clock skew. Check `date`.

## Output Conventions

When presenting results to the user:

- Prefer tables for ≤20 rows, JSON for >20 or when piping
- Always include the **region** and **account** in your summary ("In `123456789012` / `us-east-1`...")
- For destructive proposals: show ARNs, not just names
- Quote raw error strings exactly — never paraphrase AWS errors
