# demo-df

Django REST API template with production-ready AWS infrastructure (ECS Fargate + RDS + ALB).


**Live:** https://dfdemo.space/api/v1/docs

---

## Stack

| Layer | Technology |
|-------|-----------|
| Backend | Django, Django REST Framework |
| Database | PostgreSQL (RDS) |
| Container | Docker, AWS ECS Fargate (Spot) |
| Infrastructure | Terraform, AWS (ECS, RDS, ALB, ECR, SSM) |
| CI/CD | GitHub Actions |
| Auth | JWT (djangorestframework-simplejwt) |

---

## Local Development

### Option 1: Docker Compose (recommended)

**Prerequisites:** Docker, Docker Compose

```bash
docker-compose -f docker-compose.local.yml up -d
```

API docs: http://localhost:8000/api/v1/docs

```bash
# Stop
docker-compose -f docker-compose.local.yml down
```

---

### Option 2: Manual

**Prerequisites:** PostgreSQL, [uv](https://docs.astral.sh/uv/)

```bash
uv sync
source .venv/bin/activate        # Windows: .venv\Scripts\activate

cp .env.example .env             # fill in your values

python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

API docs: http://localhost:8000/api/v1/docs

---

### Option 3: Docker (manual build)

```bash
docker build \
  --build-arg ENV=dev \
  --build-arg SECRET_KEY=your_key \
  --build-arg ALLOWED_HOSTS=localhost \
  --build-arg HOST=http://localhost:8000/ \
  --build-arg DB_NAME=django_template \
  --build-arg DB_USERNAME=your_username \
  --build-arg DB_PASSWORD=your_password \
  --build-arg DB_HOST=host.docker.internal \
  --build-arg DB_PORT=5432 \
  --build-arg JWT_SIGNING_KEY=your_key \
  --build-arg CORS_ALLOWED_ORIGINS=http://localhost:8000 \
  -t django-template:latest .

docker run -p 8000:80 django-template
```

---

## CI/CD & Infrastructure

### GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | push/PR to master, dev | Lint + tests |
| `deploy.yml` | push to master | Build image → push ECR → deploy ECS |
| `terraform-ci.yml` | PR to master (terraform/**) | fmt + validate + plan + tfsec |
| `terraform-cd.yml` | push to master (terraform/**) | Terraform apply |
| `terraform-bootstrap.yml` | manual only | One-time infra prerequisites setup |
| `terraform-destroy.yml` | manual only | Teardown all infra |

All workflows support manual trigger via **Actions → Run workflow**.

### Bootstrap (first-time setup)

See `terraform/bootstrap/` — creates S3 state bucket, DynamoDB lock table, and GitHub OIDC IAM role. Run once, then delete the bootstrap IAM user.

### Required GitHub Secrets & Variables

**Secrets:**
- `TF_VAR_DB_PASSWORD`, `TF_VAR_SECRET_KEY`, `TF_VAR_JWT_SIGNING_KEY`
- `TF_VAR_GITHUB_TOKEN`, `TF_VAR_BASTION_PUBLIC_KEY`
- `TERRAFORM_ROLE_ARN` *(set automatically by bootstrap)*

**Variables:**
- `TF_VAR_DOMAIN_NAME`, `TF_VAR_CORS_ALLOWED_ORIGINS`, `TF_VAR_CERTIFICATE_ARN`
- `TF_VAR_GITHUB_REPO`, `TF_VAR_ALARM_EMAIL`
- `TF_STATE_BUCKET`, `TF_STATE_LOCK_TABLE`, `AWS_ACCOUNT_ID` *(set automatically by bootstrap)*

---

## Pre-commit Hooks

```bash
pre-commit install
```

---

## License

Copyright (c) 2023 Digital Fortress. See [LICENSE](LICENSE).

## About

<a href="https://www.digitalfortress.dev/">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://digitalfortress-s3-bucket-vpcxuhhdwecuj.s3.amazonaws.com/Group+1410083530.svg">
    <img alt="Digital Fortress logo" src="https://digitalfortress-s3-bucket-vpcxuhhdwecuj.s3.amazonaws.com/Group+1410083530.svg" width="160">
  </picture>
</a>

Made and maintained by [Digital Fortress](https://www.digitalfortress.dev) — R&D, software, hardware, cross-platform mobile and DevOps.

[GitHub](https://github.com/digitalfortress-dev) · [Website](https://www.digitalfortress.dev)
