# EC2 CLI Reference

## Inspect instances

```bash
# table of running instances with name tag
aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Az:Placement.AvailabilityZone,Ip:PrivateIpAddress,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table

# by tag
aws ec2 describe-instances --filters Name=tag:Env,Values=prod

# by id
aws ec2 describe-instances --instance-ids i-0abc...
```

## Lifecycle (mutating — confirm first)

```bash
aws ec2 stop-instances     --instance-ids i-...
aws ec2 start-instances    --instance-ids i-...
aws ec2 reboot-instances   --instance-ids i-...
aws ec2 terminate-instances --instance-ids i-...     # IRREVERSIBLE
```

`stop` is recoverable (state preserved). `terminate` deletes the instance. `--dry-run` is supported on all of these — use it.

## Security groups

```bash
aws ec2 describe-security-groups \
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId}' \
  --output table

# show ingress rules for one SG
aws ec2 describe-security-groups --group-ids sg-... \
  --query 'SecurityGroups[0].IpPermissions'
```

Editing ingress/egress is destructive — confirm CIDR + port + SG with user before:

```bash
aws ec2 authorize-security-group-ingress --group-id sg-... \
  --protocol tcp --port 22 --cidr 1.2.3.4/32

aws ec2 revoke-security-group-ingress --group-id sg-... \
  --protocol tcp --port 22 --cidr 1.2.3.4/32
```

## Volumes & snapshots

```bash
aws ec2 describe-volumes \
  --query 'Volumes[].{Id:VolumeId,Size:Size,State:State,Attached:Attachments[0].InstanceId}' \
  --output table

aws ec2 create-snapshot --volume-id vol-... --description "msg"
aws ec2 describe-snapshots --owner-ids self
```

## SSM Session Manager (preferred over SSH)

```bash
aws ssm start-session --target i-0abc...
```

Requires SSM agent on instance + IAM role. Better than opening port 22.

## Common errors

- `InvalidInstanceID.NotFound` — wrong region. Check `--region`.
- `UnauthorizedOperation` — IAM perms; show full error with `--debug` to extract encoded auth message and decode with `aws sts decode-authorization-message`.
