# Lambda CLI Reference

## Inspect

```bash
aws lambda list-functions \
  --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Mem:MemorySize,Timeout:Timeout}' \
  --output table

aws lambda get-function --function-name F            # config + code URL
aws lambda get-function-configuration --function-name F
aws lambda list-versions-by-function --function-name F
aws lambda list-aliases --function-name F
aws lambda get-policy --function-name F              # resource policy
```

## Invoke

```bash
# sync, capture response
aws lambda invoke --function-name F \
  --payload "$(echo '{"k":"v"}' | base64)" \
  /tmp/out.json && cat /tmp/out.json

# newer CLI (v2): --cli-binary-format raw-in-base64-out lets you pass raw JSON
aws lambda invoke --function-name F \
  --cli-binary-format raw-in-base64-out \
  --payload '{"k":"v"}' /tmp/out.json

# async (no response)
aws lambda invoke --function-name F --invocation-type Event /tmp/out.json
```

`/tmp/out.json` receives the function return. Logs go to CloudWatch.

## Deploy / update

```bash
# update code from local zip
aws lambda update-function-code --function-name F --zip-file fileb://pkg.zip

# update code from S3
aws lambda update-function-code --function-name F \
  --s3-bucket B --s3-key pkg.zip

# update config (env vars, memory, etc.)
aws lambda update-function-configuration --function-name F \
  --memory-size 512 --timeout 30 \
  --environment 'Variables={LOG_LEVEL=info}'

# publish a versioned snapshot
aws lambda publish-version --function-name F
```

`update-function-configuration` **replaces** the entire `Environment` block — read existing vars first or you wipe them.

## Logs

```bash
# tail recent logs (CLI v2)
aws logs tail /aws/lambda/F --follow --since 10m

# one-shot last 5 min
aws logs tail /aws/lambda/F --since 5m
```

## Layers

```bash
aws lambda list-layers
aws lambda list-layer-versions --layer-name L
aws lambda publish-layer-version --layer-name L --zip-file fileb://layer.zip
```

## Common errors

- `ResourceNotFoundException: Function not found` — wrong region or wrong alias.
- `InvalidRequestContentException` — payload not valid JSON or wrong base64 mode.
- `Code storage limit exceeded` — clean up old versions: `delete-function --qualifier <ver>`.
