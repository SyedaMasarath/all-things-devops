# AWS EKS Production Platform

A production-grade, cloud-native platform built on AWS EKS. This project demonstrates end-to-end platform engineering — from infrastructure design and IaC to CI/CD pipelines, observability, and security hardening.

> **Quick start (no AWS required):**
> ```bash
> git clone https://github.com/SyedaMasarath/all-things-devops.git
> cd all-things-devops/aws-eks-platform
> docker compose up --build
> # Frontend → http://localhost:3000  |  API → http://localhost:8080
> ```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            GitHub Actions CI/CD                              │
│                                                                              │
│  PR Opened          Merge to main              Every deploy                  │
│  ──────────         ────────────               ────────────                  │
│  terraform plan     terraform apply            Build & Push → ECR            │
│  tfsec scan         (dev → prod)               Trivy image scan              │
│  infracost          Slack notify               Helm deploy → EKS             │
│  PR comment                                    Rollback on failure           │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────────────┐
│                              AWS (us-east-1)                                 │
│                                                                              │
│  ┌─────────────────────────── VPC 10.0.0.0/16 ───────────────────────────┐  │
│  │                                                                         │  │
│  │  Public Subnets (3 AZs)          ┌─────────────────┐                  │  │
│  │  ┌──────────────────────┐        │   ALB (HTTPS)   │                  │  │
│  │  │  NAT Gateway × 3     │        └────────┬────────┘                  │  │
│  │  └──────────────────────┘                 │                            │  │
│  │                                           │                            │  │
│  │  Private Subnets (3 AZs)                  ▼                            │  │
│  │  ┌───────────────────────────────────────────────────────────────┐     │  │
│  │  │                        EKS Cluster                             │     │  │
│  │  │                                                                │     │  │
│  │  │   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │     │  │
│  │  │   │ System nodes │  │  App nodes   │  │ Monitoring nodes │   │     │  │
│  │  │   │ t3.medium ×3 │  │ m5.xlarge×3+│  │  m5.large ×2    │   │     │  │
│  │  │   │ (CoreDNS,    │  │ (api-service,│  │ (Prometheus,    │   │     │  │
│  │  │   │  kube-proxy) │  │  frontend)   │  │  Grafana, Loki) │   │     │  │
│  │  │   └──────────────┘  └──────────────┘  └──────────────────┘   │     │  │
│  │  └───────────────────────────────────────────────────────────────┘     │  │
│  │                                                                         │  │
│  │  Intra Subnets (3 AZs — no internet route)                             │  │
│  │  ┌─────────────────────────────────────────────┐                       │  │
│  │  │  Aurora PostgreSQL  (writer + 1 reader)      │                       │  │
│  │  └─────────────────────────────────────────────┘                       │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ECR (image registry)   Secrets Manager (DB creds)   KMS (encryption)      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Tool | Why this, not X |
|---|---|---|
| Infrastructure as Code | Terraform | See [Why Terraform](#why-terraform) |
| Container Orchestration | EKS 1.29 | See [Why EKS](#why-eks) |
| Package Manager | Helm 3 | See [Why Helm](#why-helm) |
| CI/CD | GitHub Actions | See [Why GitHub Actions](#why-github-actions) |
| Observability | Prometheus + Grafana + Loki | See [Why Prometheus](#why-prometheus-not-cloudwatch) |
| Secret Management | AWS Secrets Manager + ESO | No secrets in Git, automatic rotation |
| Container Registry | Amazon ECR | Native IAM auth, immutable tags, image scanning |
| Database | Aurora PostgreSQL | See [Why Aurora](#why-aurora) |
| Sample App | Go (stdlib only) | Zero dependencies, static binary, distroless image |

---

## Infrastructure Design Decisions

### Why Terraform?

**Chosen over:** AWS CloudFormation, AWS CDK, Pulumi

Terraform was chosen because:

- **Provider ecosystem** — The AWS provider is the most battle-tested IaC provider in existence. Any new AWS service gets a Terraform provider within days of GA.
- **Separation of state from code** — The plan/apply split (enforced in CI) means what was *reviewed* is exactly what gets *applied*. CloudFormation's change sets are less readable and harder to enforce in pipelines.
- **Modules as reusable components** — This project treats each `terraform/modules/` directory as an independently versioned unit. The same `eks` module works in both `dev` and `prod` environments with different variable inputs, preventing config drift.
- **Not CDK because** — CDK generates CloudFormation under the hood, so you inherit CloudFormation's limitations (stack size limits, slower feedback loops) while also adding a compilation step.
- **Not Pulumi because** — Pulumi's value is using general-purpose languages. For infrastructure that is fundamentally declarative (VPCs, node groups, IAM), that added complexity isn't worth it.

**State design:**
```
S3 (KMS encrypted) ← terraform state
DynamoDB           ← state locking (prevents concurrent applies)
```
Separate state buckets per environment (dev/prod) means a botched prod apply can never corrupt dev state.

---

### Why EKS?

**Chosen over:** ECS Fargate, Lambda, raw EC2

- **Workload portability** — Kubernetes manifests are cloud-agnostic. The same Helm chart that runs on EKS can run on GKE or AKS. ECS tasks are AWS-proprietary.
- **Richer scheduling controls** — Node taints, topology spread constraints, pod anti-affinity, and PodDisruptionBudgets give fine-grained control over *where* and *how* pods run. ECS has no equivalent.
- **Managed control plane** — EKS manages the API server, etcd, and controller manager. We only manage node groups and add-ons.
- **IRSA (IAM Roles for Service Accounts)** — Pods get AWS credentials scoped to their specific IAM role without ever touching EC2 instance profiles. This is a fundamental security improvement over ECS task roles because the scope is per-pod, not per-node.
- **Not Fargate because** — Fargate has no node-level visibility, can't run DaemonSets (needed for log collection and metrics agents), and costs significantly more for sustained workloads.

**Node group design — three separate groups:**

| Node Group | Instance | Taint | Purpose |
|---|---|---|---|
| System | t3.medium × 3 | `CriticalAddonsOnly=true:NoSchedule` | CoreDNS, kube-proxy, CNI. Isolated so application pods can't accidentally consume system capacity |
| Application | m5.xlarge × 3–20 | None | API service and frontend. Auto-scaled by Cluster Autoscaler |
| Monitoring | m5.large × 2 | `monitoring=true:NoSchedule` | Prometheus, Grafana, Loki. Isolated so a noisy application can't starve the monitoring stack |

The taint on System and Monitoring nodes means only pods that explicitly `tolerate` those taints can run there. This prevents accidental scheduling of application pods onto these nodes.

---

### Why a 3-Tier VPC?

The VPC uses three subnet tiers, not two. Most tutorials use public + private. This adds a third:

```
Public   → ALB, NAT Gateways (has internet route via IGW)
Private  → EKS nodes (egress only via NAT, no inbound from internet)
Intra    → Aurora RDS (NO internet route at all — not even egress)
```

**Why Intra subnets?**
Aurora only needs to accept connections from the EKS node security group. It should never initiate or receive connections from the internet, even via NAT. Placing it in a subnet with no route table entry to 0.0.0.0/0 makes this impossible at the network layer — no IAM policy, no security group misconfiguration can accidentally expose it.

**Why NAT Gateway per AZ (3 NAT Gateways)?**
A single NAT Gateway is a common cost-saving shortcut that creates a single point of failure. If the AZ hosting the NAT Gateway goes down, all private subnets in the other AZs lose internet egress. Three NAT Gateways (one per AZ) ensures egress is truly HA.

**VPC Endpoints:**
S3, ECR API, ECR Docker, and Secrets Manager endpoints are deployed. Traffic to these services flows through the AWS backbone instead of the internet — reducing NAT Gateway data costs and removing the internet as a path to AWS service APIs.

---

### Why Helm?

**Chosen over:** Raw kubectl manifests, Kustomize, ArgoCD

- **Parameterised templates** — The same `helm/charts/app-platform` chart deploys to dev (2 replicas, t3.large nodes) and prod (3+ replicas, m5.xlarge nodes, stricter limits) using different `values-dev.yaml` / `values-prod.yaml` overlays. No duplication.
- **Release history and rollback** — `helm rollback api-service 3` rolls back to revision 3 in seconds. The deploy workflow does this automatically on failure.
- **`--atomic` flag** — If any pod fails to become `Ready` within the timeout, Helm rolls the entire release back automatically. Raw `kubectl apply` has no equivalent.
- **Not Kustomize because** — Kustomize works well for simple value overrides, but doesn't support release management, rollback, or the rich templating needed for things like dynamically built IRSA annotations.
- **Not ArgoCD because** — ArgoCD is a valid choice for GitOps pull-based deployments. It wasn't added here to keep the scope focused, but the Helm chart structure is fully compatible with ArgoCD — adding it is a one-step `Application` manifest.

---

### Why GitHub Actions?

**Chosen over:** Jenkins, GitLab CI, CircleCI

- **No infrastructure to maintain** — Jenkins requires a controller, agents, plugins, and updates. GitHub Actions runs on GitHub-managed runners — zero ops overhead.
- **OIDC authentication** — GitHub Actions gets short-lived AWS credentials via OIDC federation. No long-lived access keys anywhere. This is a zero-secret CI/CD model.
- **Native PR integration** — The `terraform-plan.yml` workflow posts the plan output directly as a PR comment. With Jenkins, this requires a plugin; with GitHub Actions, it's three lines of `github-script`.
- **`environment` protection rules** — The `prod` environment requires a manual approval in the GitHub UI before `terraform apply` or Helm deploy runs. This is enforced at the platform level, not by shell logic.

**Pipeline design — four separate workflows:**

```
terraform-plan.yml    Triggered on: PR touching terraform/
├── terraform fmt check
├── terraform validate
├── terraform plan (matrix: dev + prod)
├── Post plan as PR comment
├── tfsec security scan → SARIF upload to GitHub Security
└── Infracost cost estimate

terraform-apply.yml   Triggered on: merge to main touching terraform/
├── Apply → Dev (auto, plan-then-apply in same job)
└── Apply → Prod (requires GitHub Environment approval)

build-push.yml        Triggered on: push to main (non-infra paths)
├── go vet + unit tests
├── Trivy filesystem scan
├── Docker build (multi-arch: amd64 + arm64)
├── Push to ECR
└── Trivy image scan (blocks on CRITICAL)

deploy.yml            Triggered on: build-push success
├── Helm deploy → Dev (smoke test after)
└── Helm deploy → Prod (rolling update, --atomic, Slack notify)
```

---

### Why Prometheus? (Not CloudWatch)

**Chosen over:** CloudWatch Container Insights, Datadog

- **Pull-based model** — Prometheus scrapes targets on its schedule. Adding a new metric to a service means adding a `/metrics` endpoint — no SDK, no agent, no configuration change in a central system.
- **PromQL** — The Prometheus query language is purpose-built for time-series data. CloudWatch's Metrics Insights query language is significantly less expressive.
- **Grafana dashboards** — Grafana + Prometheus is the industry standard. Every SRE already knows it. CloudWatch dashboards are AWS-only knowledge.
- **Cost** — Prometheus stores metrics on-cluster, PVC for persistence, CloudWatch charges per metric, per API call, and per log ingestion. At scale, CloudWatch costs become significant.
- **Not Datadog because** — Datadog is excellent but costs $15-23/host/month. For a platform this size, that's $150-300/month just for monitoring.

**Three-node isolation:**
The monitoring stack runs on dedicated nodes with a `monitoring=true:NoSchedule` taint. This means even if the application node group is maxed out and the Cluster Autoscaler is scaling, Prometheus and Grafana are unaffected. You don't lose visibility exactly when you need it most.

---

### Why Aurora PostgreSQL?

**Chosen over:** RDS PostgreSQL single instance, DynamoDB

- **Aurora's storage layer is shared across all instances** — a writer and up to 15 readers all read from the same distributed storage. Failover to a reader takes ~30 seconds vs minutes for standard RDS.
- **Automatic failover** — If the writer fails, Aurora promotes a reader automatically. No manual intervention, no data loss for committed transactions.
- **Storage auto-scaling** — Aurora storage grows automatically. No need to provision and manage storage capacity.
- **Intra subnets** — RDS is placed in subnets with no internet route. DB credentials are rotated automatically every 30 days by Secrets Manager. The password in `terraform.tfstate` (S3/KMS encrypted) is the only place it ever lives in plaintext — and even that is rotated automatically.

---

## Security Posture

| Control | Implementation |
|---|---|
| **No long-lived credentials** | GitHub Actions uses OIDC. EKS nodes use IRSA per-addon |
| **Secrets never in Git** | Secrets Manager + External Secrets Operator. `terraform.tfvars` is gitignored |
| **KMS everywhere** | EKS secrets, EBS volumes, ECR images, S3 state, Secrets Manager — all use CMKs |
| **IMDSv2 enforced** | `http_tokens = required` in the launch template — blocks SSRF-based credential theft |
| **Zero-trust networking** | Default-deny NetworkPolicy in `production` namespace. Each service explicitly allows only required traffic |
| **Non-root containers** | `runAsNonRoot: true`, `runAsUser: 1000`, distroless final image (Go API) |
| **Read-only filesystem** | `readOnlyRootFilesystem: true` on all containers |
| **Drop ALL capabilities** | `capabilities.drop: [ALL]` — containers have no Linux capabilities |
| **Image scanning** | Trivy on every push. CRITICAL findings block the build. Results uploaded to GitHub Security |
| **Infra scanning** | tfsec on every PR. SARIF results uploaded to GitHub Security |
| **Pod Security Standards** | Enforced via Helm chart security contexts (restricted baseline) |
| **RDS in isolated subnets** | Intra subnets have no internet route — impossible to reach from outside the VPC |
| **Secret rotation** | Secrets Manager rotates DB password every 30 days via managed rotation Lambda |

---

## High Availability Design

| Component | HA Mechanism |
|---|---|
| EKS nodes | Spread across 3 AZs. `TopologySpreadConstraints` enforces ≤1 pod skew per zone |
| NAT Gateway | One per AZ (3 total) — AZ failure doesn't kill egress for other AZs |
| Aurora | Writer + 1 reader. Automatic failover in ~30s |
| ALB | Cross-zone load balancing enabled |
| Rolling deploys | `maxUnavailable: 0`, `maxSurge: 1` — zero old pods are killed before a new one is `Ready` |
| PodDisruptionBudgets | Managed by each Helm chart (`podDisruptionBudget.enabled: true` in values). api-service and frontend use `minAvailable: 1`; frontend also accepts `maxUnavailable: 50%`. Prometheus, Alertmanager, and Grafana PDBs configured in `helm/monitoring/values.yaml` |
| Cluster Autoscaler | Scales node groups 3–20 based on pending pods |

---

## Project Structure

```
aws-eks-platform/
├── services/api/                # Go API service (zero dependencies)
│   ├── main.go                  # HTTP server: /health, /metrics, /api/v1/status
│   ├── main_test.go             # Unit tests (httptest, stdlib only)
│   ├── go.mod                   # Go 1.22 module
│   └── Dockerfile               # Multi-stage: golang:alpine → distroless:nonroot
├── frontend/                    # nginx status dashboard
│   ├── src/index.html           # Dark-themed live status dashboard
│   ├── nginx.conf               # Static serving + /api/ reverse proxy + security headers
│   └── Dockerfile               # Multi-stage: node:alpine → nginx:alpine (non-root)
├── terraform/
│   ├── modules/
│   │   ├── vpc/                 # VPC, 3-tier subnets, NAT HA, VPC endpoints, flow logs
│   │   ├── eks/                 # Cluster, 3 node groups, IRSA, add-ons, KMS
│   │   ├── rds/                 # Aurora PostgreSQL, Secrets Manager, auto-rotation
│   │   ├── alb/                 # AWS Load Balancer Controller IRSA
│   │   └── monitoring/          # Cluster Autoscaler IRSA
│   └── environments/
│       ├── dev/                 # Dev workspace (smaller instances, 1 RDS instance)
│       └── prod/                # Prod workspace (HA sizing, deletion protection on)
├── kubernetes/
│   ├── namespaces/              # Namespace definitions
│   ├── rbac/                    # Developer / SRE / platform-team roles
│   └── network-policies/        # Zero-trust: default deny + explicit allowlist
│   # Note: PodDisruptionBudgets are managed by each Helm chart, not here
├── helm/
│   ├── charts/app-platform/     # Reusable chart: probes, HPA, PDB, IRSA, ServiceMonitor
│   ├── charts/frontend/         # nginx frontend chart
│   └── monitoring/              # kube-prometheus-stack values
├── .github/workflows/
│   ├── terraform-plan.yml       # PR: plan + tfsec + infracost
│   ├── terraform-apply.yml      # Merge: apply dev → prod (with approval gate)
│   ├── build-push.yml           # Test → build → Trivy scan → push ECR
│   └── deploy.yml               # Helm deploy dev → prod (rolling update, --atomic)
├── scripts/
│   ├── bootstrap.sh             # One-time: S3 state bucket, DynamoDB lock, GitHub OIDC
│   └── validate.sh              # Pre-deploy: cluster reachability, namespace checks
├── docs/runbooks/
│   └── incident-response.md     # P1-P4 severity definitions + kubectl runbook
├── docker-compose.yml           # Local dev: full stack, no AWS required
└── Makefile                     # make help — all commands documented
```

---

## Getting Started

### Prerequisites

```bash
aws-cli  >= 2.x      # brew install awscli
terraform >= 1.7.0   # brew install terraform
kubectl  >= 1.29     # brew install kubectl
helm     >= 3.14     # brew install helm
go       >= 1.22     # brew install go          (for local dev only)
docker              # Docker Desktop
```

### Local Development (no AWS)

```bash
# Run everything locally
docker compose up --build

# API:      http://localhost:8080/api/v1/status
# Frontend: http://localhost:3000
# Metrics:  http://localhost:8080/metrics

# Run Go tests
cd services/api && go test ./... -race -v
```

### Deploy to AWS

```bash
# 1. Bootstrap remote state (run once per account)
./scripts/bootstrap.sh all

# 2. Deploy dev infrastructure
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # fill in your VPN CIDR
terraform init && terraform plan -out=tfplan
terraform apply tfplan

# 3. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name eks-platform-dev --alias dev

# 4. Install monitoring stack
make monitoring-install

# 5. Apply Kubernetes base manifests
kubectl apply -k kubernetes/

# 6. Deploy application
helm upgrade --install api-service helm/charts/app-platform \
  -f helm/charts/app-platform/values-dev.yaml \
  --namespace applications --create-namespace
```

### Useful Commands

```bash
make help                    # all available targets
make tf-plan ENVIRONMENT=prod
make kubeconfig ENVIRONMENT=dev
make helm-diff               # preview changes before deploying
make scan-terraform          # tfsec locally
make grafana-port-forward    # http://localhost:3000
terraform output             # cluster endpoint, ECR URLs, DB secret ARN
```

---

## Observability

| Signal | Tool | Access |
|---|---|---|
| Metrics | Prometheus + Grafana | `make grafana-port-forward` → localhost:3000 |
| Logs | Loki + Grafana | Same Grafana instance, Explore tab |
| Traces | (OpenTelemetry ready) | Instrument app with OTEL SDK, point to collector |
| Alerts | Alertmanager → Slack/PagerDuty | Configured in `helm/monitoring/values.yaml` |

The Go API exposes Prometheus metrics at `/metrics` without any external library — the format is implemented directly using `fmt.Fprintf`. The Helm chart's `ServiceMonitor` resource tells Prometheus to scrape it every 30s.

---

## CI/CD Pipeline

```
PR opened
  └─► terraform-plan.yml
        ├── fmt check
        ├── validate
        ├── plan (dev + prod matrix)
        ├── Post plan as PR comment
        ├── tfsec → GitHub Security tab
        └── Infracost cost delta

Merge to main
  ├─► terraform-apply.yml
  │     ├── Apply → dev  (automatic)
  │     └── Apply → prod (requires GitHub Environment approval)
  │
  └─► build-push.yml
        ├── go vet + unit tests + coverage
        ├── Trivy filesystem scan
        ├── Docker build (linux/amd64 + linux/arm64)
        ├── Push to ECR (immutable tag: sha-<short>)
        └── Trivy image scan (exit 1 on CRITICAL)
              │
              └─► deploy.yml
                    ├── Helm deploy → dev
                    │     └── Smoke test (pod ready + /health endpoint)
                    └── Helm deploy → prod
                          ├── Rolling update (maxUnavailable: 0, --atomic)
                          ├── GitHub Deployment API (tracks in UI)
                          ├── Auto-rollback on failure
                          └── Slack notification (always)
```

---

## License

MIT
