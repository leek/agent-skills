# CloudWatch Logs CLI Reference

## Tail (CLI v2 — preferred)

```bash
aws logs tail /aws/lambda/F                       # last 10 min
aws logs tail /aws/lambda/F --since 1h
aws logs tail /aws/lambda/F --follow              # live stream
aws logs tail /aws/lambda/F --filter-pattern ERROR
aws logs tail /aws/lambda/F --format short        # less noise
```

`--since` accepts: `5m`, `2h`, `3d`, ISO timestamp.

## List log groups / streams

```bash
aws logs describe-log-groups \
  --query 'logGroups[].logGroupName' --output text

aws logs describe-log-streams --log-group-name /aws/lambda/F \
  --order-by LastEventTime --descending --max-items 5 \
  --query 'logStreams[].logStreamName' --output text
```

## Filter events (older API, more control)

```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/F \
  --start-time $(($(date +%s%3N) - 3600000)) \
  --filter-pattern '"timeout"' \
  --query 'events[].{t:timestamp,m:message}' \
  --output table
```

Times are **milliseconds since epoch**. Use `date +%s%3N` (GNU) or `gdate +%s%3N` (macOS).

## Logs Insights (queries — powerful)

```bash
# start a query
QID=$(aws logs start-query \
  --log-group-name /aws/lambda/F \
  --start-time $(($(date +%s) - 3600)) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | limit 50' \
  --query queryId --output text)

# poll until complete
aws logs get-query-results --query-id "$QID"
```

## Retention & deletion

```bash
aws logs put-retention-policy --log-group-name /aws/lambda/F --retention-in-days 14
aws logs delete-log-group --log-group-name /aws/lambda/F   # DESTRUCTIVE
```

## Common errors

- `ResourceNotFoundException: The specified log group does not exist` — wrong region or function never invoked.
- Times in ms (not seconds) for `filter-log-events` — easy off-by-1000.
- macOS `date` lacks `%3N`; use `gdate` (`brew install coreutils`) or compute: `$(($(date +%s) * 1000))`.
