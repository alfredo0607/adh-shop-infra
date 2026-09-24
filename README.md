# ADH Shop — Infrastructure

Terraform for the ADH Shop storefront. Single environment.

## Layout

```
terraform/
├── bootstrap/
│   └── remote-state/          S3 bucket holding every other stack's state
├── infrastructures/           Deployable stacks
│   ├── network/               VPC, public and private tiers, gateway endpoints
│   ├── data-store/            DynamoDB
│   ├── container-api-ec2/     ECR, scripts bucket, container host
│   └── cdn-web-spa/           S3 + CloudFront for the SPA
├── modules/                   Reusable modules, one per resource group
├── user-data/                 Instance boot scripts, rendered by templatefile()
└── scripts/                   Operational scripts, uploaded to S3
```

Stacks are separated by rate of change and blast radius. The network changes
rarely; the application changes constantly. A mistake while deploying the API
must not be able to touch routing.

## Network tiers

| Tier | Contents | Why |
| --- | --- | --- |
| Public | Container host (nginx + containers), elastic IP | Must answer on 80/443, and certbot's HTTP-01 challenge needs an inbound connection on port 80 |
| Private | Reserved for the cache | No route to an internet gateway at all — stronger than a security group rule, because even a misconfigured group cannot expose it |

**There is no NAT gateway.** A NAT costs roughly 32 USD/month and is only needed
when something in the private tier must reach the internet. Nothing here does.
DynamoDB and S3 are reached through **gateway endpoints**, which are free and
keep that traffic off the public internet entirely.

## First run

```bash
# 1. Create the state bucket. Local state, applied once.
cd terraform/bootstrap/remote-state
terraform init && terraform apply

# 2. Point the other stacks at it
cd ../..
cp backend.hcl.example backend.hcl      # fill in the bucket name

# 3. Apply in dependency order
for stack in network data-store container-api-ec2; do
  cd infrastructures/$stack
  cp terraform.tfvars.example terraform.tfvars   # where one exists
  terraform init -backend-config=../../backend.hcl
  terraform apply
  cd ../..
done
```

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
- **SSH defaults to closed**, and the module *rejects* `0.0.0.0/0`. Session
  Manager is available through the instance role and needs no open port.
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

## Storefront delivery

The built SPA lives in a private bucket reached only through CloudFront with
Origin Access Control, so the TLS, the security headers and the caching cannot
be bypassed by addressing the bucket directly.

Setting `api_origin_domain_name` makes CloudFront serve the API under `/api/*`
from the same domain as the SPA. The browser then never issues a cross-origin
request: no preflight, no `Access-Control-*` headers, one certificate, and the
API inherits the same security headers as the front end.

Two cache behaviours, because one size does not fit: `/assets/*` is cached for a
year (the bundler puts a content hash in every filename), while `index.html`
is not (or a release would take a day to appear). API responses are never
cached at the edge — one customer's transaction served to another is not a
theoretical risk.

`403` and `404` are rewritten to `/index.html` with a `200` so client-side
routing works. Without it, refreshing any page other than the root is an error.

Deploy with the command printed by `terraform output deploy_command`.

## Pending

- The private tier is provisioned but empty, awaiting the rate-limit cache.
