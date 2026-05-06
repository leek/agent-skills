# Secrets Manager & SSM Parameter Store CLI Reference

Two services, similar use cases:

- **Secrets Manager** — rotation, KMS by default, $0.40/secret/month + API. Best for credentials with rotation needs.
- **SSM Parameter Store** — free tier (Standard params), no rotation. Best for non-secret config + small secrets without rotation.

Both encrypt with KMS. Both integrate with ECS/Lambda env injection.

## Secrets Manager

### Read

```bash
# get the value (newest version)
aws secretsmanager get-secret-value --secret-id prod/api/db \
  --query SecretString --output text

# parse JSON secret
aws secretsmanager get-secret-value --secret-id prod/api/db \
  --query SecretString --output text | jq -r .password

# specific version
aws secretsmanager get-secret-value --secret-id prod/api/db \
  --version-stage AWSPREVIOUS

# metadata only (no value)
aws secretsmanager describe-secret --secret-id prod/api/db
```

### List

```bash
aws secretsmanager list-secrets \
  --query 'SecretList[].{Name:Name,Updated:LastChangedDate,Rotation:RotationEnabled}' \
  --output table

# filter by tag
aws secretsmanager list-secrets \
  --filters Key=tag-key,Values=Environment \
  --filters Key=tag-value,Values=production
```

### Create / update

```bash
# string secret
aws secretsmanager create-secret --name prod/api/db \
  --secret-string '{"username":"admin","password":"hunter2"}' \
  --kms-key-id alias/aws/secretsmanager

# update value (creates new version)
aws secretsmanager put-secret-value --secret-id prod/api/db \
  --secret-string '{"username":"admin","password":"hunter3"}'

# update metadata (description, KMS key, rotation)
aws secretsmanager update-secret --secret-id prod/api/db \
  --description "API DB creds"
```

`put-secret-value` creates a new version with stages `AWSCURRENT` (new) and `AWSPREVIOUS` (old). `AWSPENDING` is the rotation work-in-progress slot.

### Rotation

```bash
aws secretsmanager rotate-secret --secret-id prod/api/db \
  --rotation-lambda-arn arn:aws:lambda:us-east-1:123:function:rotator \
  --rotation-rules AutomaticallyAfterDays=30

aws secretsmanager rotate-secret --secret-id prod/api/db   # trigger immediate rotation
```

### Delete

```bash
# soft-delete with 30-day recovery window
aws secretsmanager delete-secret --secret-id prod/api/db \
  --recovery-window-in-days 30

# IRREVERSIBLE — bypasses recovery
aws secretsmanager delete-secret --secret-id prod/api/db \
  --force-delete-without-recovery

# restore (within recovery window)
aws secretsmanager restore-secret --secret-id prod/api/db
```

Always confirm before `--force-delete-without-recovery`. Default recovery is 30 days.

## SSM Parameter Store

Three tiers: `String`, `StringList` (CSV), `SecureString` (KMS-encrypted). Standard params: free, 4KB, 10k limit. Advanced params: $0.05/month, 8KB, no count limit.

### Read

```bash
# single parameter
aws ssm get-parameter --name /app/prod/db/host \
  --query Parameter.Value --output text

# encrypted parameter — must pass --with-decryption
aws ssm get-parameter --name /app/prod/db/password \
  --with-decryption \
  --query Parameter.Value --output text

# multiple by name
aws ssm get-parameters --names /app/prod/db/host /app/prod/db/port \
  --with-decryption \
  --query 'Parameters[].{Name:Name,Value:Value}' --output table

# everything under a path (great for env loading)
aws ssm get-parameters-by-path --path /app/prod/ \
  --recursive --with-decryption \
  --query 'Parameters[].{Name:Name,Value:Value}' --output table
```

`--with-decryption` is silently ignored on non-`SecureString` params — safe to always include.

### List

```bash
aws ssm describe-parameters \
  --query 'Parameters[].{Name:Name,Type:Type,Modified:LastModifiedDate}' \
  --output table

# filter by path
aws ssm describe-parameters \
  --parameter-filters Key=Name,Option=BeginsWith,Values=/app/prod/
```

### Create / update

```bash
# string
aws ssm put-parameter --name /app/prod/db/host \
  --value "db.example.com" --type String

# secure string (KMS-encrypted)
aws ssm put-parameter --name /app/prod/db/password \
  --value "hunter2" --type SecureString \
  --key-id alias/aws/ssm

# update existing (--overwrite required)
aws ssm put-parameter --name /app/prod/db/host \
  --value "db2.example.com" --type String --overwrite
```

Without `--overwrite`, `put-parameter` fails on existing keys — useful safety default.

### Delete

```bash
aws ssm delete-parameter --name /app/prod/db/host
aws ssm delete-parameters --names /app/prod/db/host /app/prod/db/port
```

No soft-delete or recovery — gone is gone. Confirm before deleting.

### History

```bash
aws ssm get-parameter-history --name /app/prod/db/host \
  --query 'Parameters[].{Version:Version,Value:Value,Modified:LastModifiedDate}'
```

## Choosing between them

| Need | Use |
|---|---|
| Automatic rotation | Secrets Manager |
| Cross-region replication | Secrets Manager |
| Hierarchical config (`/app/prod/...`) | Parameter Store |
| Free | Parameter Store (Standard) |
| Resource policies | Secrets Manager (richer) |
| Lambda/ECS env injection | Both work — Secrets Manager via `secrets`, Param Store via `secrets` (yes, same key) |

## Mutating ops — confirm first

- `delete-secret --force-delete-without-recovery`
- `delete-parameter` / `delete-parameters` (no recovery)
- `put-parameter --overwrite` on production paths
- `put-secret-value` on `AWSCURRENT` (immediate effect on consumers)

## Common errors

- **`ResourceNotFoundException`** — wrong name, wrong region, or wrong account. Names are case-sensitive.
- **`AccessDeniedException` on encrypted secret/param** — caller has the secret/SSM perm but not `kms:Decrypt` on the CMK. Add KMS policy.
- **`ParameterAlreadyExists`** — pass `--overwrite` (and confirm with user first).
- **Secrets Manager `InvalidRequestException: ... scheduled for deletion`** — secret is in 30-day recovery window. Use `restore-secret`.
