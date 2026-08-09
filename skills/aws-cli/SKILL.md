---
name: aws-cli
description: Run AWS CLI commands safely — identity and region first, prefer read-only, confirm before mutating. Use when the user runs or asks for `aws` CLI work across S3, EC2, IAM, Lambda, Logs, ECS, or related services.
---

# AWS CLI

Run AWS CLI commands safely and efficiently. Default to **read-only** operations. Always confirm identity, region, and blast radius before mutating anything.

## Always Do First

Before any AWS CLI command, establish identity, region, and profile.

**Fast path — resolve context from local config, no network call.** Region and a cached account ID both come from local files, so there's no need for an `sts` round-trip:

```bash
# env vars win (CI, direnv); else fall back to the active profile's ~/.aws/config
ACCT="${AWS_EXPECTED_ACCOUNT_ID:-$(aws configure get expected_account_id 2>/dev/null)}"
REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null)}"
echo "context: ${ACCT:-?} / ${REGION:-?}  (profile ${AWS_PROFILE:-default})"
```

If both resolve, **skip the upfront `aws sts get-caller-identity` round-trip** — treat them as the known account and region. Any auth problem (missing creds, expired SSO) surfaces on the first real command, so the check buys nothing for read-only work. State the assumed context in your summary ("Using cached context `123456789012` / `us-east-1`").

`region` is a standard CLI key. `expected_account_id` is a **custom** key — the CLI ignores it, but `aws configure get` reads it. Stash it once, per profile, so it travels with the credentials it describes:

```bash
aws configure set expected_account_id 123456789012 --profile <name>
```

**Cold path — context didn't resolve.** Confirm three things first:

1. **Identity** — `aws sts get-caller-identity` (account, principal)
2. **Region** — explicit `--region <r>` or `AWS_REGION` env. Do not rely on default profile region for cross-account work.
3. **Profile** — `AWS_PROFILE=<name>` if multiple. Show user which profile is active.

If `aws sts get-caller-identity` fails: stop. Do not retry blindly. Diagnose: missing creds, expired SSO session, wrong profile. See [references/auth.md](./references/auth.md).

**Verify before mutating.** The fast path trusts the *expected* account; it does not prove you're authenticated as it. Before any destructive op or work against a `prod` account, confirm the live identity matches the cache:

```bash
[ "$(aws sts get-caller-identity --query Account --output text)" = "$ACCT" ] \
  && echo "identity OK" || echo "ACCOUNT MISMATCH — stop"
```

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

## Disable Pager in Scripts

CLI v2 pipes long output through `less` by default. In a non-interactive shell (CI, agent runs, `bash -c`) this can hang. Always disable it:

```bash
export AWS_PAGER=""        # for the session
aws --no-cli-pager s3 ls   # for one command
```

Set `AWS_PAGER=""` at the top of any script that calls `aws`.

## Wait for Resource State

Don't poll with `sleep` loops. The CLI has built-in waiters that poll for you:

```bash
aws ec2 wait instance-running    --instance-ids i-0abc...
aws ec2 wait instance-terminated --instance-ids i-0abc...
aws lambda wait function-updated --function-name F
aws s3api wait bucket-exists     --bucket B
aws cloudformation wait stack-create-complete --stack-name S
```

List available waiters per service: `aws <service> wait help`.

Default poll interval and max attempts are service-specific (usually 15s × 40 attempts = 10 min).

## Discovery & Skeleton Generation

For unfamiliar commands, two power tools:

```bash
# interactive parameter completion — picks args from prompts
aws lambda create-function --cli-auto-prompt

# generate a JSON skeleton of all params, fill in, then submit
aws lambda create-function --generate-cli-skeleton > req.json
# edit req.json
aws lambda create-function --cli-input-json file://req.json
```

Useful for any command with >5 params or nested shapes.

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
- **ECS / Fargate** — see [references/ecs.md](./references/ecs.md)
- **DynamoDB** — see [references/dynamodb.md](./references/dynamodb.md)
- **Secrets Manager / SSM Parameter Store** — see [references/secrets.md](./references/secrets.md)

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
