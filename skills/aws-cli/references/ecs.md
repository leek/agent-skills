# ECS / Fargate CLI Reference

ECS = clusters → services → tasks → containers. Fargate is a launch type (serverless); EC2 launch type uses your own instances.

## Inspect

```bash
aws ecs list-clusters \
  --query 'clusterArns[]' --output text

aws ecs list-services --cluster prod \
  --query 'serviceArns[]' --output text

aws ecs describe-services --cluster prod --services api \
  --query 'services[0].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount,TaskDef:taskDefinition}' \
  --output table

aws ecs list-tasks --cluster prod --service-name api \
  --query 'taskArns[]' --output text

aws ecs describe-tasks --cluster prod --tasks <taskArn> \
  --query 'tasks[0].{Status:lastStatus,Health:healthStatus,Stopped:stoppedReason}'
```

## Task definitions

```bash
# list
aws ecs list-task-definitions --family-prefix api --status ACTIVE \
  --query 'taskDefinitionArns[]' --output text

# describe (dump full def)
aws ecs describe-task-definition --task-definition api:42

# register new revision from JSON
aws ecs register-task-definition --cli-input-json file://taskdef.json

# generate skeleton when authoring
aws ecs register-task-definition --generate-cli-skeleton > taskdef.json
```

## Deploy

```bash
# update service to new task def revision
aws ecs update-service --cluster prod --service api \
  --task-definition api:43

# force-pull latest image (same task def)
aws ecs update-service --cluster prod --service api \
  --force-new-deployment

# wait for rollout
aws ecs wait services-stable --cluster prod --services api
```

`services-stable` waits up to 10 min (40 × 15s) for `runningCount == desiredCount` and no in-progress deployments.

## Scale

```bash
aws ecs update-service --cluster prod --service api --desired-count 4
```

Or attach Application Auto Scaling to the service for dynamic scaling.

## Run a one-off task (Fargate)

```bash
aws ecs run-task --cluster prod \
  --launch-type FARGATE \
  --task-definition migrate:7 \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-abc],securityGroups=[sg-xyz],assignPublicIp=DISABLED}' \
  --query 'tasks[0].taskArn' --output text
```

## Exec into a running task (ECS Exec)

Requires `enableExecuteCommand=true` on the task definition + `ssm:StartSession` perms on the task role.

```bash
aws ecs execute-command --cluster prod --task <taskArn> \
  --container app --interactive --command "/bin/sh"
```

## Logs

Container stdout goes to CloudWatch via the `awslogs` log driver. Tail:

```bash
aws logs tail /ecs/api --follow --since 10m
```

## Mutating ops — confirm first

- `update-service --desired-count 0` (effective takedown)
- `delete-service` (must scale to 0 first or pass `--force`)
- `delete-cluster`
- `stop-task` (kills running task immediately)
- `deregister-task-definition`

## Common errors

- **`CannotPullContainerError`** — image not in ECR or task role lacks `ecr:GetAuthorizationToken`.
- **`ResourceInitializationError: unable to pull secrets`** — secret ARN wrong or task execution role missing `secretsmanager:GetSecretValue` / `ssm:GetParameters`.
- **Task starts then stops immediately** — check `stoppedReason` in `describe-tasks`. Common: app crashes on boot, or healthcheck fails.
- **`Subnet ... has no available IP addresses`** — ENI exhaustion in the subnet; use a larger CIDR or different subnet.
