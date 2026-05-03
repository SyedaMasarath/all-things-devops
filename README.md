# All Things DevOps

> A living collection of production-grade DevOps projects, reference architectures, and hard-won learnings from working as a Senior DevOps / Platform Engineer.

This repository is not tutorials. Everything here reflects real decisions made in real environments — including the tradeoffs, the "why not X", and the operational realities that don't make it into blog posts.

---

## About

I'm a Senior DevOps Engineer with hands-on experience building and operating cloud-native platforms on AWS, with a focus on:

- **Platform Engineering** — Internal developer platforms, self-service infrastructure, golden paths
- **Infrastructure as Code** — Terraform at scale, modular design, state management, drift prevention  
- **Kubernetes** — EKS/GKE, multi-tenant clusters, workload isolation, HA patterns
- **CI/CD** — GitHub Actions, GitOps, progressive delivery, zero-downtime deployments
- **Observability** — Prometheus, Grafana, Loki, alerting strategy, SLOs
- **Security** — Zero-trust networking, IRSA/OIDC, secrets management, container hardening

Each project in this repo is built to production standards — not "good enough for a demo." Code is reviewed as if it's going to a real cluster with real traffic.

---

## Projects

### 🚀 [aws-eks-platform](./aws-eks-platform/) — Production EKS Reference Architecture

> *End-to-end cloud-native platform on AWS EKS with full GitOps CI/CD, observability stack, and security hardening.*

A complete, opinionated reference architecture for running production workloads on AWS EKS. Built to answer the question: *what does a well-engineered Kubernetes platform actually look like?*

**What's inside:**

| Component | Details |
|---|---|
| **VPC** | 3-tier (public/private/intra), NAT HA per AZ, VPC endpoints, flow logs |
| **EKS** | 3 isolated node groups (system/app/monitoring), IRSA, KMS secrets, IMDSv2 |
| **RDS** | Aurora PostgreSQL, intra subnets (no internet route), Secrets Manager + auto-rotation |
| **CI/CD** | 4 GitHub Actions workflows: plan, apply, build+scan, deploy |
| **Security** | Zero-trust NetworkPolicy, RBAC, distroless images, non-root, drop-ALL caps |
| **Observability** | Prometheus (HA) + Grafana + Loki + Alertmanager → Slack/PagerDuty |
| **App** | Go API (stdlib only) + nginx frontend, docker-compose for local dev |

**Key design decisions documented:**
- Why Terraform over CloudFormation/CDK
- Why 3 NAT Gateways (not 1)
- Why intra subnets for RDS
- Why Prometheus over CloudWatch
- Why distroless over Alpine final images

```bash
# Run the full stack locally — no AWS account needed
git clone https://github.com/SyedaMasarath/all-things-devops
cd all-things-devops/aws-eks-platform
docker compose up --build
# Frontend → http://localhost:3000  |  API → http://localhost:8080
```

→ **[Full documentation and architecture](./aws-eks-platform/README.md)**

---

### 📌 Coming Soon

Projects I'm actively working on or planning to add:

| Project | Description | Status |
|---|---|---|
| `platform-tooling` | Internal CLI tooling for developer self-service (Go) | Planning |
| `observability-stack` | Standalone Prometheus + Grafana + Loki setup with runbooks and alert library | Planning |
| `gitops-argocd` | ArgoCD-based GitOps deployment with progressive delivery (canary + blue-green) | Planning |
| `terraform-modules` | Reusable, versioned Terraform modules for common AWS patterns | Planning |
| `incident-runbooks` | Real-world runbooks for common production incidents | In progress |

---

## Engineering Principles

These are the principles that guide how I build. Not aspirational — observable in the code:

**1. Explicit over implicit**
Every default is intentional. Variables that could cause security incidents (like `public_access_cidrs`) have no default or block dangerous values with `validation` blocks. Nobody should be able to apply this infrastructure and accidentally open the EKS API to the internet.

**2. The reviewer should see exactly what gets applied**
The CI/CD pattern enforced here: `terraform plan -out=tfplan` → review the plan → `terraform apply tfplan`. The apply is always the exact plan that was reviewed — never a fresh drift calculation. This is the difference between "we have CI" and "CI actually provides a safety guarantee."

**3. Failure should be loud and fast**
`--atomic` on Helm deployments. `set -euo pipefail` in every shell script. Validation blocks on Terraform variables. Trivy blocking on CRITICAL. The system should scream before something gets into production, not page you at 2am after it does.

**4. Operations is part of the design**
Runbooks are in the repo. Monitoring is on isolated nodes so it survives an app-tier incident. The architecture anticipates operational failure modes, not just happy paths.

**5. Document the why, not just the what**
Any engineer can read code and understand what it does. The value of documentation is capturing *why* this approach was chosen over alternatives, what the tradeoffs are, and what would need to change if requirements changed.

---

## Repository Structure

```
all-things-devops/
├── aws-eks-platform/    # Production EKS reference architecture (Terraform + Helm + GitHub Actions)
├── knowledge-base/      # Notes, patterns, and lessons learned
└── README.md            # This file
```

---

## Working With This Repo

Each project is self-contained with its own README, local development setup, and prerequisites. Start with the project's README — it will tell you exactly what you need.

For `aws-eks-platform` specifically:

```bash
# Prerequisites
brew install terraform kubectl helm go awscli

# Local dev (no AWS needed)
cd aws-eks-platform
docker compose up --build

# Deploy to AWS (after running bootstrap.sh)
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars  # fill in your VPN CIDR
terraform init && terraform plan -out=tfplan && terraform apply tfplan
```

---

## Connect

If something here was useful, raised a question, or you spotted something worth improving — open an issue or reach out.

> *"Most DevOps problems are not technical problems. They are coordination problems with a technical surface area."*
