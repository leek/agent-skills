# IAM CLI Reference

IAM is global — no `--region` needed. Mutations are sensitive; always confirm.

## Identity & policies

```bash
aws sts get-caller-identity                     # whoami
aws iam get-user                                # current user (if user creds)

aws iam list-users   --query 'Users[].UserName'  --output text
aws iam list-roles   --query 'Roles[].RoleName'  --output text
aws iam list-groups  --query 'Groups[].GroupName' --output text
```

## Inspect a role

```bash
aws iam get-role --role-name R
aws iam list-attached-role-policies --role-name R
aws iam list-role-policies --role-name R         # inline policies
aws iam get-role-policy --role-name R --policy-name P
aws iam get-policy --policy-arn arn:aws:iam::aws:policy/X
aws iam get-policy-version --policy-arn arn:... --version-id v1
```

## Trust policy (who can assume this role)

```bash
aws iam get-role --role-name R --query Role.AssumeRolePolicyDocument
```

## Inspect a user

```bash
aws iam list-attached-user-policies --user-name U
aws iam list-user-policies --user-name U
aws iam list-groups-for-user --user-name U
aws iam list-access-keys --user-name U
```

## Simulate a policy (read-only, very useful)

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123:role/R \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::bucket/key
```

## Mutations — confirm before any of these

```bash
aws iam create-role / delete-role
aws iam attach-role-policy / detach-role-policy
aws iam put-role-policy / delete-role-policy
aws iam create-access-key / delete-access-key
aws iam create-user / delete-user
aws iam add-user-to-group / remove-user-from-group
```

## Decode encoded auth failure

When you see `Encoded authorization failure message: <blob>`:

```bash
aws sts decode-authorization-message --encoded-message "<blob>" \
  --query DecodedMessage --output text | jq
```

Reveals the exact action, resource, and condition that failed.

## Common pitfalls

- IAM changes can be **eventually consistent** — wait a few seconds before retrying after policy edits.
- A role with no `AssumeRolePolicyDocument` trust for your principal will fail `sts:AssumeRole` even if attached policies look right.
- `*` in resources is rarely what you want in production.
