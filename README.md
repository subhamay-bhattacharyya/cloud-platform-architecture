# cloud-platform-architecture

Foundational setup and onboarding guides for the multi-cloud platforms used
across the **Cloud Champion Bootcamp** projects. This repository captures the
one-time bootstrap steps — organization hierarchy, identities, roles, and
CI/CD wiring — that must be in place before any Terraform-managed workloads
are deployed.

## Platforms

| Platform | Scope | Documentation |
| --- | --- | --- |
| Google Cloud Platform | Organization hierarchy, shared CI/CD project, Workload Identity Federation for GitHub Actions, and the IAM roles required for Terraform automation. | [gcp/README.md](./gcp/README.md) |
| Snowflake | Custom role provisioning, GitHub Actions service user with key-pair authentication, and the analyst read-only role for the Snowflake Lakehouse project. | [snowflake/SNOWFLAKE_ONBOARDING.md](./snowflake/SNOWFLAKE_ONBOARDING.md) |
| HCP Terraform | HCP Terraform organization and workspace setup, GitHub OAuth app for VCS integration, and the GitHub Actions secrets used by Terraform workflows. | [hcp-cloud/README.md](./hcp-cloud/README.md) |

## Repository Layout

```text
.
├── gcp/                         # GCP org + CI/CD bootstrap
│   ├── README.md
│   └── get_github_cicd_vars.sh
├── hcp-cloud/                   # HCP Terraform + GitHub OAuth bootstrap
│   └── README.md
└── snowflake/                   # Snowflake roles + service user bootstrap
    ├── SNOWFLAKE_ONBOARDING.md
    └── snowflake-custom-roles.sql
```

## Goals

- Establish a **least-privilege** baseline for each cloud before Terraform
  takes over day-to-day management.
- Standardize **keyless CI/CD** authentication — OIDC on GCP and key-pair
  authentication on Snowflake.
- Keep all bootstrap steps **reproducible and auditable** by versioning the
  SQL scripts, shell helpers, and onboarding runbooks in this repository.

## Getting Started

1. Pick the platform you need to onboard and open its guide above.
2. Follow the prerequisites section to confirm account access and required
   admin roles.
3. Run the bootstrap steps in order, substituting any placeholders called
   out in each document.
4. Hand off to the Terraform workflows once the bootstrap checks pass.
