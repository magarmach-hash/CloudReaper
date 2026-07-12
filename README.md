# CloudReaper

**Self-cleaning cloud infrastructure.** Deploy test environments with a time-to-live, and CloudReaper automatically destroys them when they expire — even if you forget.

---

## How It Works

```
Developer deploys with TTL tag
        |
        v
  Lambda scans every 5 min
  (EventBridge schedule)
        |
        v
  Finds expired resources
  (reads expiry_time tag)
        |
        v
  Fires GitHub repository_dispatch
        |
        v
  GitHub Actions runs
  terraform destroy
```

**One sentence:** EventBridge wakes Lambda every 5 minutes, Lambda scans AWS for tagged resources and checks if their expiry time has passed, and if expired, Lambda triggers a GitHub Actions workflow that runs `terraform destroy`.

---

## Architecture

### Control Plane (deploy once)

| Resource | Purpose |
|---|---|
| `cloudreaper-lambda` | Python 3.12 Lambda that scans for expired resources |
| `cloudreaper-schedule` | EventBridge rule firing every 5 minutes |
| `cloudreaper-lambda-role` | IAM role — `tagging:GetResources` + `secretsmanager:GetSecretValue` + CloudWatch Logs |

### Workloads (deploy/destroy repeatedly, one folder per project)

Each project lives in its own folder under `workloads/` with its own Terraform state (isolated via a unique S3 backend key). Resources are tagged with:

- `project = "<folder-name>"` — tells Lambda which project to destroy
- `expiry_time = "<ISO 8601 UTC>"` — the source of truth for when to destroy
- `managed-by = "cloudreaper"` — discoverability tag

### GitHub Actions Pipelines

| Pipeline | Trigger | What it does |
|---|---|---|
| `setup-control-plane.yml` | Manual, run once | Deploys Lambda + EventBridge |
| `deploy-workload.yml` | Manual (`workflow_dispatch`) | Computes expiry, runs `terraform apply` |
| `destroy-workload.yml` | Automatic (`repository_dispatch`) | Runs `terraform destroy` on expired project |

---

## Quick Start

### Prerequisites

- AWS account with budget alerts configured
- GitHub repository with these secrets:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
- A GitHub PAT with `repo` scope, stored in AWS Secrets Manager (the built-in `GITHUB_TOKEN` cannot fire `repository_dispatch` events)
- An S3 bucket named `cloudreaper-state` (for Terraform state)
- Terraform 1.10+ (installed by the workflows)

### 1. Store the GitHub PAT in Secrets Manager

```bash
aws secretsmanager create-secret \
  --name cloudreaper/github-pat \
  --secret-string "ghp_your_token_here"
```

Note the ARN from the output (you'll need it as a GitHub Actions variable).

### 2. Deploy the Control Plane

Set a repository variable `CLOUDREAPER_SECRET_ARN` with the Secrets Manager ARN from step 1, then go to **Actions > CloudReaper — Setup Control Plane > Run workflow**, type `yes`, and run it.

### 3. Deploy a Workload

Go to **Actions > CloudReaper — Deploy Workload > Run workflow**, pick a project and a TTL (in hours), and run it.

### 4. Watch It Work

Lambda runs every 5 minutes. When resources expire, `destroy-workload.yml` triggers automatically.

Or trigger a manual destroy via the GitHub CLI:

```bash
gh api repos/{owner}/{repo}/dispatches \
  -f event_type=cloudreaper-destroy \
  -f client_payload='{"project":"example-project"}'
```

---

## Adding a New Project

1. Create a new folder under `workloads/` (e.g., `workloads/my-new-project/`)
2. Add `backend.tf` with a unique S3 key (e.g., `cloudreaper/my-new-project/terraform.tfstate`)
3. Tag all resources with `project`, `expiry_time`, and `managed-by = "cloudreaper"`
4. Add the project name to the `deploy-workload.yml` workflow's `project` choice list

Lambda will automatically detect and manage it — no code changes needed.

---

## Why Lambda Triggers Terraform Instead of Deleting Directly

Real infrastructure has dependencies (EC2 inside a subnet inside a VPC). Deleting out of order fails. Terraform already solves dependency-ordered teardown via its state graph. Lambda's only job is *deciding when*, not *how*.

---

## Cost Safety Checklist

- [ ] Set up an AWS Budget with alerts at $1 and $5 **before** deploying
- [ ] Use short TTLs (5-10 min) while testing the automation
- [ ] Keep a manual `terraform destroy` ready as fallback
- [ ] After testing, verify in the AWS console that nothing is left running
- [ ] Check for leftover CloudWatch Log Groups (not destroyed by `terraform destroy` unless explicitly managed)

**Control plane cost:** $0 at this scale — Lambda and EventBridge scheduled rules are part of AWS's Always Free tier.

---

## Known Limitations

- **State drift:** If resources are deleted outside this pipeline (manually in the console), Terraform state can drift. A production version would add periodic `terraform refresh` reconciliation.
- **GitHub token expiry:** The PAT used for `repository_dispatch` must remain valid. Consider using a GitHub App for long-term use.

---

## Project Structure

```
CloudReaper/
├── README.md
├── control-plane/
│   ├── main.tf              # Lambda + EventBridge + IAM
│   ├── variables.tf         # github_secret_arn, github_owner, github_repo
│   ├── backend.tf           # S3 state: cloudreaper/control-plane/
│   └── lambda/
│       └── scanner.py       # Tag scanning + GitHub dispatch logic
├── workloads/
│   └── example-project/
│       ├── main.tf          # VPC + EC2 with expiry tags
│       ├── variables.tf     # expiry_time, ttl_hours, project_name
│       ├── outputs.tf
│       └── backend.tf       # S3 state: cloudreaper/example-project/
└── .github/
    └── workflows/
        ├── setup-control-plane.yml
        ├── deploy-workload.yml
        └── destroy-workload.yml
```
