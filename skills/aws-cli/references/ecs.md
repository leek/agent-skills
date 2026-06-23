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

### Gotchas (non-interactive shells, one-shot commands)

- **Pick a *ready* task — not blindly `taskArns[0]`.** `enableExecuteCommand` on the *service* doesn't mean every task can exec; during a rolling deploy new tasks sit in `ACTIVATING`/`PENDING` with the exec agent still `PENDING`, and exec fails with *"execute command was not enabled … or the execute command agent isn't running."* Confirm both are `RUNNING` first:
  ```bash
  aws ecs describe-tasks --cluster prod --tasks "$TASK_ID" \
    --query "tasks[0].{status:lastStatus,agent:containers[0].managedAgents[0].lastStatus}" --output json
  # → {"status":"RUNNING","agent":"RUNNING"} — both must say RUNNING
  ```
- **`Cannot perform start session: EOF`** from a non-interactive shell (CI, an agent, a piped call): `--interactive` needs stdin held open. Redirect from `/dev/null` for a one-shot, or `sleep 25 |` to hold the session open. A *trailing* `Cannot perform start session: EOF` / `Exiting session …` line **after** the output is just normal teardown, not an error.
- **No `bash` in slim images.** Wrap pipelines in `sh -c "..."`, not `bash -lc` (fails with `bash: executable file not found in $PATH`).
- **SSM adds ~5–10s startup latency** before any output appears, and the call may get backgrounded — give it time before assuming it failed. Strip ANSI control noise from captured output with `sed -E 's/\x1b\[[0-9;]*m//g'`.

### Run a multi-line script in the container (base64 → /tmp)

Quoting a multi-line program through `execute-command` is hopeless, and many REPLs (e.g. PHP's psysh `tinker --execute`) reject `use` statements / multi-line input. Encode locally, decode in the container, run it, then `cat` a result file the script wrote:

```bash
B64=$(base64 -i /tmp/script.ext | tr -d '\n')
aws ecs execute-command --cluster prod --task "$TASK_ID" --container app --interactive \
  --command "sh -c \"echo $B64 | base64 -d > /tmp/x.ext && <interpreter> /tmp/x.ext </dev/null >/dev/null 2>&1; echo '=====OUTPUT====='; cat /tmp/out.txt\""
```

Have the script **write its result to `/tmp/out.txt`** (not stdout) and `cat` it *after* the interpreter exits: REPLs often swallow an included file's stdout, and `</dev/null` forces the interpreter to exit instead of hanging forever on the pty. The `=====OUTPUT=====` sentinel separates real output from session noise.

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
