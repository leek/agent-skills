# JMESPath Patterns for `--query`

JMESPath filters AWS CLI JSON output before display. Faster than piping to `jq` and removes pagination noise.

## Basic projections

```bash
# pick fields
--query 'Reservations[].Instances[].InstanceId'

# pick fields into named object
--query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType}'

# nested field
--query 'Reservations[].Instances[].State.Name'
```

## Filtering

```bash
# equality
--query 'Reservations[].Instances[?State.Name==`running`].InstanceId'

# negation
--query 'Reservations[].Instances[?State.Name!=`terminated`]'

# contains
--query 'Reservations[].Instances[?contains(Tags[?Key==`Env`].Value, `prod`)]'

# numeric compare
--query 'Volumes[?Size>`100`].VolumeId'
```

Backticks `` ` `` quote string/number literals inside the query.

## Tag value extraction

Tags come as `[{Key,Value}, ...]`. Pick one:

```bash
--query 'Reservations[].Instances[].Tags[?Key==`Name`]|[0].Value'
# or, flat
--query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,Id:InstanceId}'
```

## Sort & limit

```bash
# sort by field, take first 10
--query 'reverse(sort_by(Buckets, &CreationDate))[:10].Name'

# count
--query 'length(Reservations[].Instances[])'
```

## Common AWS shapes

| Service | Path to items |
|---|---|
| `ec2 describe-instances` | `Reservations[].Instances[]` |
| `s3api list-buckets` | `Buckets[]` |
| `iam list-roles` | `Roles[]` |
| `lambda list-functions` | `Functions[]` |
| `logs describe-log-groups` | `logGroups[]` |
| `rds describe-db-instances` | `DBInstances[]` |
| `cloudformation list-stacks` | `StackSummaries[]` |

## Output format pairs well with --query

- `--output table` — auto-renders `{key:value}` projections as a table
- `--output text` — newline/tab separated, perfect for `xargs` / shell loops
- `--output json` — pipe to `jq` for further processing
