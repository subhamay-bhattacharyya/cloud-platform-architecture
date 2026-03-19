# GCP Organization Bootstrap Setup for Terraform

This guide documents the **recommended enterprise setup for managing GCP organization hierarchy using Terraform**.  
It starts with creating a **dedicated project inside a shared platform folder** to host the Terraform service account that will manage folders and projects in the organization.

The service account will later be used by **GitHub Actions via Workload Identity Federation (OIDC)**.

---

# 1. GCP Resource Hierarchy

Create the following structure in your organization:

```
Organization
│
├── fld-platform-shared
│     └── prj-shared-github-cicd
│           └── sa-github-terraform
│
├── fld-production
│
├── fld-nonproduction
│
└── fld-sandbox
```

### Purpose

| Component | Purpose |
|---|---|
| **fld-platform-shared** | Contains shared platform infrastructure |
| **prj-shared-github-cicd** | Dedicated project for CI/CD identities and automation |
| **sa-github-terraform** | Terraform automation service account |

This project **does not host workloads**. It is used only for:

- Terraform automation
- CI/CD identities
- Workload Identity Federation
- Cross-project infrastructure management

---

# 2. Complete Prerequisite Identity Setup

Before proceeding with organization bootstrap, complete the following identity prerequisites:

1. Sign up for a domain name.
2. Create a Google Workspace for that domain.
3. Create a Google account in the Google Workspace tenant.
4. Log in to Google Cloud using the Google Workspace login ID.

---

# 3. Retrieve Organization ID

Authenticate and retrieve the organization ID.

```bash
gcloud auth login
gcloud organizations list
```

Example output:

```
DISPLAY_NAME        ID
subhamay.cloud      123456789012
```

Store it:

```bash
ORG_ID="123456789012"
```

---

# 4. Create the Platform Shared Folder

Create a folder to host shared platform services.

```bash
# List the project you have access to, typically this is the default project when you create a GCP account
gcloud projects list --format="value(projectId,projectNumber)"

gcloud resource-manager folders create \
  --display-name="fld-platform-shared" \
  --organization=$ORG_ID
```

Example output:

```
name: folders/123456789012
displayName: fld-platform-shared
```

Store the folder ID:

```bash
FOLDER_ID="123456789012"
```

---

# 5. Create the CI/CD Identity Project

Create a project inside the **platform shared folder**.

```bash
gcloud projects create prj-shared-github-cicd-06902 \
  --name="prj-shared-github-cicd" \
  --folder=$FOLDER_ID
```

Set the project for CLI usage:

```bash
gcloud config set project prj-shared-github-cicd-06902
```

---

# 6. Enable Required APIs

Enable APIs required for IAM, federation, and automation.

```bash
gcloud services enable \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com
```

---

# 7. Create Terraform Service Account

Create the service account used by Terraform automation.

```bash
gcloud iam service-accounts create sa-github-terraform \
  --display-name="GitHub Terraform Service Account" \
  --description="Service account used by GitHub Actions via Workload Identity Federation to run Terraform deployments across GCP projects"
```

Verify creation:

```bash
gcloud iam service-accounts list
```

Expected output:

```
sa-github-terraform@prj-shared-github-cicd-06902.iam.gserviceaccount.com
```

Store the service account email:

```bash
SA_EMAIL="sa-github-terraform@prj-shared-github-cicd-06902.iam.gserviceaccount.com"
```

---

# 8. Grant Organization Roles to the Service Account

### Folder Administration

```bash
gcloud organizations add-iam-policy-binding $ORG_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/resourcemanager.folderAdmin"
```

### Project Creation

```bash
gcloud organizations add-iam-policy-binding $ORG_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/resourcemanager.projectCreator"
```

### Project IAM Administration

```bash
gcloud organizations add-iam-policy-binding $ORG_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/resourcemanager.projectIamAdmin"
```

---

# 9. Retrieve Billing Account

Projects require a billing account during creation.

```bash
gcloud billing accounts list
```

Example output:

```
ACCOUNT_ID           NAME
000ABC-123DEF-456GHI My Billing Account
```

Store billing ID:

```bash
BILLING_ID="000ABC-123DEF-456GHI"
```

---

# 10. Grant Billing Permission

Allow Terraform to attach billing accounts to new projects.

```bash
gcloud billing accounts add-iam-policy-binding $BILLING_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/billing.user"
```

---

# 11. Verify IAM Permissions

Verify organization roles:

```bash
gcloud organizations get-iam-policy $ORG_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_EMAIL" \
  --format="table(bindings.role)"
```

Verify billing permissions:

```bash
gcloud billing accounts get-iam-policy $BILLING_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_EMAIL" \
  --format="table(bindings.role)"
```

---

# 12. Test Terraform Service Account Permissions

### Create Test Folder

```bash
gcloud resource-manager folders create \
  --display-name="fld-test-terraform" \
  --organization=$ORG_ID \
  --impersonate-service-account=$SA_EMAIL
```

Save the folder ID:

```bash
TEST_FOLDER_ID="FOLDER_ID_FROM_OUTPUT"
```

### Create Test Project

```bash
gcloud projects create prj-test-bootstrap-001 \
  --name="prj-test-bootstrap-001" \
  --folder=$TEST_FOLDER_ID \
  --impersonate-service-account=$SA_EMAIL
```

### Attach Billing

```bash
gcloud billing projects link prj-test-bootstrap-001 \
  --billing-account=$BILLING_ID \
  --impersonate-service-account=$SA_EMAIL
```

---

# 13. Configure GitHub OIDC Authentication (Workload Identity Federation)

This step allows **GitHub Actions to authenticate to GCP without service account keys**.

---

## Retrieve Project Number

Workload Identity Pools require the project number.

```bash
PROJECT_ID="prj-shared-github-cicd-06902"

PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID \
  --format="value(projectNumber)")
```

---

## 1. Set Required Variables

```bash
PROJECT_ID="prj-shared-github-cicd-06902"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
POOL_ID="github-actions"
PROVIDER_ID="github-provider"
SA_EMAIL="sa-github-terraform@prj-shared-github-cicd-06902.iam.gserviceaccount.com"
```

Define the GitHub organizations you want to trust:

```bash
GITHUB_ORGS=("org1" "org2" "org3")
```

---

## Create Workload Identity Pool

```bash
gcloud iam workload-identity-pools create github-actions \
  --project=$PROJECT_ID \
  --location=global \
  --display-name="GitHub Actions Pool"
```

---

## Create GitHub OIDC Provider

Replace with your GitHub repository.

```bash
GITHUB_ORG="YOUR_GITHUB_ORG"
GITHUB_REPO="YOUR_REPO"
```

```bash
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project=$PROJECT_ID \
  --location=global \
  --workload-identity-pool=github-actions \
  --display-name="GitHub Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref,attribute.actor=assertion.actor" \
  --attribute-condition="assertion.repository_owner=='org1' || assertion.repository_owner=='org2'"
```

Optional (recommended) restriction to main branch:

```
assertion.repository=='ORG/REPO' && assertion.ref=='refs/heads/main'
```

---

## Allow GitHub Organizations  to Impersonate the Service Account

Grant `roles/iam.workloadIdentityUser` to each GitHub organization by using `attribute.repository_owner`.

```bash
for ORG in "${GITHUB_ORGS[@]}"; do
  gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --project=$PROJECT_ID \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository_owner/${ORG}"
done
```

Grant `roles/iam.serviceAccountTokenCreator` as well:

```bash
for ORG in "${GITHUB_ORGS[@]}"; do
  gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --project=$PROJECT_ID \
    --role="roles/iam.serviceAccountTokenCreator" \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository_owner/${ORG}"
done
```

---

## Retrieve Workload Identity Provider Name

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --project=$PROJECT_ID \
  --location=global \
  --workload-identity-pool=github-actions \
  --format="value(name)"
```

Example output:

```
projects/123456789012/locations/global/workloadIdentityPools/github-actions/providers/github-provider
```

---

# 14. Configure GitHub Actions Workflow

Create a workflow:

```
.github/workflows/terraform.yml
```

Example:

```yaml
name: Terraform GCP

on:
  push:
    branches: [ main ]

permissions:
  contents: read
  id-token: write

jobs:
  terraform:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github-provider
          service_account: sa-github-terraform@prj-shared-github-cicd-06902.iam.gserviceaccount.com

      - uses: google-github-actions/setup-gcloud@v2

      - name: Verify access
        run: |
          gcloud auth list
          gcloud projects list
```

---

# Required Roles Summary

| Scope | Role | Purpose |
|---|---|---|
| Organization | `roles/resourcemanager.folderAdmin` | Create and manage folders |
| Organization | `roles/resourcemanager.projectCreator` | Create projects |
| Organization | `roles/resourcemanager.projectIamAdmin` | Assign IAM roles on projects |
| Billing Account | `roles/billing.user` | Attach billing to projects |
| Service Account | `roles/iam.workloadIdentityUser` | Allow GitHub OIDC authentication |

---

# Final Result

After completing this setup:

- GitHub Actions can authenticate to GCP using **OIDC**
- No **service account keys** are required
- Terraform can **securely manage the GCP organization hierarchy**
- CI/CD pipelines can deploy infrastructure across projects