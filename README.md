# ADH Shop — Infrastructure

Terraform for the ADH Shop storefront. Single environment.

## Layout

```
terraform/
├── bootstrap/
│   └── remote-state/          S3 bucket holding every other stack's state
├── infrastructures/
│   └── container-api-ec2/     The whole platform in one apply: network, table,
│                              registry, host, image CDN, optional cache
├── modules/                   Reusable modules, one per resource group
├── user-data/                 Instance boot scripts, rendered by templatefile()
└── scripts/                   Operational scripts, uploaded to S3
```

The API platform is one stack rather than four. Separating network, data,
registry and host was justified on blast radius — a mistake while deploying the
application should not be able to touch routing — and that argument holds when
separate teams own separate layers and change them at different rates. It does
not hold here: one person owns all of it, there is one environment, and it is
short-lived. The separation bought ceremony rather than safety, at the price of
four applies in a fixed order that had to be remembered.

The image CDN belongs here too, because it depends on the API rather than
standing beside it: CloudFront verifies signatures the API produces, so the
signing key pair, the key group and the parameter the API reads it from have to
be created together or not at all.

## Network tiers

| Tier | Contents | Why |
| --- | --- | --- |
| Public | Container host (nginx + containers), elastic IP | Must answer on 80/443, and certbot's HTTP-01 challenge needs an inbound connection on port 80 |
| Private | Valkey cache | No route to an internet gateway at all — stronger than a security group rule, because even a misconfigured group cannot expose it |

**There is no NAT gateway.** A NAT costs roughly 32 USD/month and is only needed
when something in the private tier must reach the internet. Nothing here does.
DynamoDB and S3 are reached through **gateway endpoints**, which are free and
keep that traffic off the public internet entirely.

## First run

Nothing asks for an account id or a bucket name. Both are derived from whoever
is authenticated, so the state a stack writes to always belongs to the account
it is deploying into.

```bash
export AWS_PROFILE=<a profile that can create these resources>
export AWS_REGION=us-east-1

# 1. The state bucket. Local state, applied once.
terraform -chdir=terraform/bootstrap/remote-state init
terraform -chdir=terraform/bootstrap/remote-state apply

# 2. The whole API platform.
./scripts/tf-init.sh terraform/infrastructures/container-api-ec2
terraform -chdir=terraform/infrastructures/container-api-ec2 apply
```

That is the deployment. Every input has a working default, so
`terraform.tfvars` is only needed to change one — narrowing SSH to a single
address, or turning the cache on.

### Why `tf-init.sh` rather than a backend file

A `backend` block cannot use variables. Terraform resolves it before the
variable system exists, so `bucket = var.state_bucket` is invalid by design. The
usual workaround is a `backend.hcl`, which means the account id is either
committed to a public repository or retyped by hand.

The script derives the bucket from `sts get-caller-identity` and passes it with
`-backend-config`, which removes both problems and also rules out initialising
against the wrong account's state.

State locking is native to S3 (`use_lockfile = true`, Terraform 1.10+). The
separate DynamoDB lock table older guides require is no longer needed.

## Deployment flow

```
CI ──push image──► ECR
                    │
   ┌────────────────▼─────────────────────────────────────┐
   │ EC2, public subnet, elastic IP                       │
   │                                                      │
   │  nginx :80/:443 ──upstream──► 127.0.0.1:3000 (blue)  │
   │    certbot / Let's Encrypt    127.0.0.1:3001 (green) │
   └──────────────────────────────────────────────────────┘
                    │
        SSM Parameter Store  ·  DynamoDB  ·  S3 (scripts)
```

**Once per host** — `bootstrap.sh` runs as user data: installs Docker, nginx and
certbot, configures the CloudWatch agent, downloads the management scripts and
logs in to ECR. It deploys nothing.

**Once per application** — `add-keys.sh <env-file>` publishes configuration to
Parameter Store; `add-api.sh <subdomain> <even-port> <email>` creates the nginx
upstream and virtual host and obtains the certificate.

**Every release** — `deploy.sh <image> <app>` performs a blue/green switch.

## Deployments are blue/green

`deploy.sh` starts the new version on the idle port of the pair, waits for it to
answer `/health`, then repoints the nginx upstream and reloads. Only once traffic
has moved is the old container retired.

If the new image fails to start or never becomes healthy, the deployment aborts
and the previous version is still serving. Nothing changed.

Containers publish on `127.0.0.1` only. The security group opens 80 and 443 and
nothing else, so the application is reachable exclusively through the proxy —
and therefore only over TLS.

## Configuration and secrets

Parameter Store is the source of truth. Secrets are never stored in S3, never
committed, and never written to a long-lived file on the host.

`deploy.sh` reads the parameters at deploy time into a file created with
`umask 077` and removed by a trap, so the values exist on disk only for the few
seconds Docker needs to read them. The instance role is scoped to
`/adh-shop/*`, so a compromise of this host cannot read another service's
credentials.

## Security decisions worth knowing

- **IMDSv2 required.** With IMDSv1 enabled, a single SSRF in the application is
  enough to read the instance role's temporary credentials.
- **Application ports are not in the security group.** Exposing one would let
  anyone reach the app directly over plain HTTP, bypassing nginx, the
  certificate and the HTTPS redirect.
- **SSH is open to `0.0.0.0/0` by default**, which is a deliberate choice rather
  than an oversight: it collects credential-stuffing traffic from the moment the
  address is reachable. `allowed_ssh_cidrs` narrows it to a single address, and
  an empty list closes the port entirely — Session Manager still works, since it
  needs no inbound rule.
- **Encryption at rest** on the root volume, the state bucket, the scripts
  bucket, DynamoDB and ECR.
- **VPC flow logs** record rejected traffic, so "was this host reached from
  outside?" is answerable after the fact.
- **The instance role has DynamoDB data-plane permissions only.** It cannot
  create, alter or delete a table.

## CI

Runs without AWS credentials: `terraform fmt -check`, `validate` on every stack
with `-backend=false`, `tflint`, a Trivy configuration scan, and ShellCheck over
the operational scripts.

## Image delivery

Product images live in a private bucket and are served through CloudFront
**only with a signed URL the API issues**. Possessing the address is not enough:
the URL has to have been granted, and it expires.

Two controls, and both must pass. Origin Access Control is the only path to the
bucket, so the object cannot be fetched directly. `trusted_key_groups` on the
distribution means an unsigned request is rejected at the edge, before the
origin is touched.

### The signing key never passes through Terraform

RSA 2048, which is what CloudFront requires. Generated once, outside Terraform:

```bash
openssl genrsa -out private.pem 2048
openssl rsa -pubout -in private.pem -out public_key.pem
aws s3 cp private.pem s3://<scripts bucket>/keys/cloudfront/private.pem
rm private.pem
```

Only the public half is read by Terraform, from `public_key.pem` in the stack
directory. A public key is not a secret, so it is committed — with a `.gitignore`
exception written as a full path rather than a filename, because `!public_key.pem`
on its own would let a private key slip through under that name.

The private half travels S3 → Parameter Store → deleted. `add-keys.sh` pulls it
into a directory created with mode 700, writes it as a `SecureString`, and a
trap shreds and removes that directory on any exit — success, failure or
interrupt. The window in which a private key exists on disk is the seconds
between those two steps.

Generating it in Terraform would be fewer steps, but the key would then live in
state: a file read on every plan, by anyone who can run one, long after the
moment it was needed.

CloudFront trusts a *key group* rather than a key. The indirection is what makes
rotation possible: add a second key, let clients migrate, remove the first —
with no window in which no key is valid.

## Storefront delivery

Not built yet. The SPA needs somewhere to live and it is not this CDN, whose
distribution requires a signature on every request — a browser loading
`index.html` has no signature to present.

## Rate limiter cache

Valkey Serverless in the private tier, authenticated with IAM. There is no
password anywhere — not in state, not in Parameter Store, not in an environment
variable. The host exchanges its instance role for a short-lived token on each
connection, and IAM auth requires TLS.

The cache identity is scoped to one key prefix and to read, write and scripting
commands. If the application is compromised, the blast radius on the cache is
that prefix.

`cache_usage_limits` caps storage and compute. Serverless bills by both and
neither is bounded by default, so a key leak or a deliberate attempt to inflate
the key space throttles instead of producing an unbounded bill.

Permission to connect is attached from the cache stack to the role the container
stack created, rather than granted there against a name that does not exist yet.
Both ARNs come from the resources themselves, so renaming the cache cannot leave
a stale grant behind.

Apply order: `network` → `data-store` → `container-api-ec2` → `cache`.

**Cost.** Serverless has a minimum billed storage footprint, roughly 6 to 7 USD
a month in us-east-1 even with no traffic. Valkey is materially cheaper than
Redis OSS here, but it is not free; the historic ElastiCache free tier covered
`t*.micro` nodes rather than serverless. Confirm against your own billing
console.
