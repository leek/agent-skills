# DynamoDB CLI Reference

CLI uses raw DynamoDB JSON ("AttributeValue" wire format) by default. Pass `--cli-input-json` for complex shapes, or learn the type prefixes.

## Type prefixes (AttributeValue)

| Prefix | Type | Example |
|---|---|---|
| `S` | string | `{"S":"hello"}` |
| `N` | number (as string!) | `{"N":"42"}` |
| `B` | binary (base64) | `{"B":"dGV4dA=="}` |
| `BOOL` | boolean | `{"BOOL":true}` |
| `NULL` | null | `{"NULL":true}` |
| `L` | list | `{"L":[{"S":"a"},{"S":"b"}]}` |
| `M` | map | `{"M":{"k":{"S":"v"}}}` |
| `SS`/`NS`/`BS` | string/number/binary set | `{"SS":["a","b"]}` |

Numbers are always strings on the wire. `42` → `{"N":"42"}`.

## Inspect tables

```bash
aws dynamodb list-tables --query 'TableNames[]' --output text

aws dynamodb describe-table --table-name users \
  --query 'Table.{Status:TableStatus,Items:ItemCount,Size:TableSizeBytes,Keys:KeySchema}'

aws dynamodb describe-table --table-name users \
  --query 'Table.GlobalSecondaryIndexes[].{Name:IndexName,Status:IndexStatus,Keys:KeySchema}'
```

`ItemCount` and `TableSizeBytes` are updated every ~6 hours — not real-time.

## Get item

```bash
aws dynamodb get-item --table-name users \
  --key '{"userId":{"S":"u-123"}}'

# strongly consistent read
aws dynamodb get-item --table-name users \
  --key '{"userId":{"S":"u-123"}}' \
  --consistent-read

# project specific attributes
aws dynamodb get-item --table-name users \
  --key '{"userId":{"S":"u-123"}}' \
  --projection-expression "userId, email, createdAt"
```

## Put item

```bash
aws dynamodb put-item --table-name users \
  --item '{"userId":{"S":"u-123"},"email":{"S":"a@b.com"},"active":{"BOOL":true}}'

# only insert if not exists (conditional)
aws dynamodb put-item --table-name users \
  --item '{"userId":{"S":"u-123"},"email":{"S":"a@b.com"}}' \
  --condition-expression "attribute_not_exists(userId)"
```

`put-item` overwrites by default — always pair with a condition expression for "create-only".

## Update item

```bash
aws dynamodb update-item --table-name users \
  --key '{"userId":{"S":"u-123"}}' \
  --update-expression "SET email = :e, updatedAt = :t" \
  --expression-attribute-values '{":e":{"S":"new@b.com"},":t":{"S":"2026-05-06T00:00:00Z"}}' \
  --return-values ALL_NEW
```

`--return-values`: `NONE` | `ALL_OLD` | `UPDATED_OLD` | `ALL_NEW` | `UPDATED_NEW`.

## Delete item

```bash
aws dynamodb delete-item --table-name users \
  --key '{"userId":{"S":"u-123"}}' \
  --condition-expression "attribute_exists(userId)" \
  --return-values ALL_OLD
```

Always pair destructive ops with conditions to avoid accidental no-ops/overwrites.

## Query (partition + optional sort)

```bash
aws dynamodb query --table-name orders \
  --key-condition-expression "userId = :u AND createdAt BETWEEN :a AND :b" \
  --expression-attribute-values '{":u":{"S":"u-123"},":a":{"S":"2026-01-01"},":b":{"S":"2026-12-31"}}' \
  --limit 100

# query a GSI
aws dynamodb query --table-name orders \
  --index-name byEmail \
  --key-condition-expression "email = :e" \
  --expression-attribute-values '{":e":{"S":"a@b.com"}}'
```

## Scan (avoid in production)

Reads every item. Use only on small tables or with strict filters + provisioned throughput.

```bash
aws dynamodb scan --table-name users \
  --filter-expression "active = :a" \
  --expression-attribute-values '{":a":{"BOOL":true}}' \
  --max-items 100
```

## Batch ops (25 items max)

```bash
aws dynamodb batch-get-item --request-items file://batch-get.json
aws dynamodb batch-write-item --request-items file://batch-write.json
```

`batch-write-item` does **not** support updates — only put/delete.

## Streams

```bash
aws dynamodb describe-table --table-name users \
  --query 'Table.LatestStreamArn'

aws dynamodbstreams describe-stream --stream-arn <arn>
aws dynamodbstreams get-shard-iterator --stream-arn <arn> \
  --shard-id <id> --shard-iterator-type LATEST
aws dynamodbstreams get-records --shard-iterator <iter>
```

## PartiQL (SQL-like, optional)

```bash
aws dynamodb execute-statement \
  --statement "SELECT email FROM users WHERE userId = ?" \
  --parameters '[{"S":"u-123"}]'
```

## Mutating ops — confirm first

- `delete-table` (irreversible — cannot be restored without backup)
- `update-table` switching billing mode or removing a GSI
- `restore-table-from-backup` to existing name
- Any `delete-item` / `batch-write-item` without a condition

## Common errors

- **`ValidationException: One or more parameter values were invalid`** — usually a type prefix mismatch (`{"N":42}` instead of `{"N":"42"}`).
- **`ConditionalCheckFailedException`** — your condition expression didn't match. Often the desired outcome (e.g., "create-only" hit an existing key).
- **`ProvisionedThroughputExceededException`** — switch to on-demand or raise capacity; CLI does not auto-retry indefinitely.
- **`ResourceNotFoundException`** — wrong table name or wrong region.
