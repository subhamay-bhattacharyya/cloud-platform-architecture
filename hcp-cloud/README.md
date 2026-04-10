# HCP Terraform Onboarding

This guide walks through the one-time bootstrap for running Terraform from
GitHub Actions against **HCP Terraform** (formerly Terraform Cloud). It covers
creating the HCP Terraform organization and workspace, wiring a GitHub OAuth
application as a VCS provider, and seeding the GitHub repository secrets used
by the CI/CD workflows.

## Prerequisites

- A GitHub account with **Owner** access to the target organization (required
  to register OAuth apps and manage repository secrets).
- Admin access to an HCP account at <https://portal.cloud.hashicorp.com>.
- `gh` CLI installed and authenticated (`gh auth login`) if you plan to set
  repository secrets from the command line.

---

## 1. Create an HCP Terraform Organization

1. Sign in to <https://app.terraform.io> using your HashiCorp Cloud account.
2. From the top-left organization switcher, choose **Create new organization**.
3. Enter a unique **Organization name** (e.g. `cloud-champion-bootcamp`) and
   the **Email address** that should receive notifications.
4. Click **Create organization**.

## 2. Create a Project and Workspace

1. In the left navigation, open **Projects & workspaces** → **New** →
   **Workspace**.
2. Choose the **CLI-driven workflow** for now (we will switch to VCS once the
   OAuth app is connected in Step 4).
3. Give the workspace a descriptive name (e.g. `gcp-bootstrap-dev`) and assign
   it to a project.
4. Click **Create workspace**.

## 3. Generate an HCP Terraform API Token

You need an API token so GitHub Actions can authenticate to HCP Terraform.

1. Click your user avatar (top-right) → **Account settings** → **Tokens**.
2. Under **API tokens**, click **Create an API token**.
3. Enter a description (e.g. `github-actions`) and an expiration, then
   **Generate token**.
4. **Copy the token immediately** — it is shown only once. You will store it
   as the `TF_API_TOKEN` GitHub secret in Step 6.

> For long-lived automation you can alternatively create a **Team API token**
> (Settings → Teams → *team* → **Team API token**) and scope permissions to a
> dedicated `github-actions` team.

---

## 4. Create a GitHub OAuth App for HCP Terraform VCS

HCP Terraform connects to GitHub via an OAuth application so it can read
repository contents, webhooks, and pull-request status.

1. Sign in to GitHub and open
   **Settings** → **Developer settings** → **OAuth Apps** → **New OAuth App**.
   - For org-owned apps use
     `https://github.com/organizations/<ORG>/settings/applications`.
2. Fill in the form:
   - **Application name**: `HCP Terraform - <org-name>`
   - **Homepage URL**: `https://app.terraform.io`
   - **Authorization callback URL**:
     `https://app.terraform.io/auth/<HCP-ORG-NAME>/callback`
     (HCP Terraform shows the exact callback URL in Step 5 below — copy it
     from there if unsure.)
3. Click **Register application**.
4. On the app detail page, click **Generate a new client secret**.
5. Record the **Client ID** and **Client secret** — you will paste them into
   HCP Terraform in the next step.

## 5. Register the OAuth App in HCP Terraform

1. In HCP Terraform, open **Organization settings** → **Providers** (under
   *Version Control*) → **Add a VCS provider**.
2. Choose **GitHub** → **GitHub.com (Custom)**.
3. HCP Terraform displays the exact **Authorization callback URL** — confirm
   it matches the one you entered in Step 4, then update the GitHub OAuth app
   if needed.
4. Paste the **Client ID** and **Client secret** from the GitHub OAuth app.
5. Click **Connect and continue**, then authorize the app when redirected to
   GitHub.
6. Back in HCP Terraform, give the VCS connection a name and click **Create
   VCS provider**.

Your workspaces can now be connected to GitHub repositories via **Workspace
settings** → **Version control** → **Connect to version control**.

---

## 6. Configure GitHub Repository Secrets

The Terraform GitHub Actions workflows read the HCP Terraform token and
organization name from repository secrets.

| Secret name | Value |
| --- | --- |
| `TF_API_TOKEN` | The HCP Terraform API token created in Step 3 |
| `TF_CLOUD_ORGANIZATION` | The HCP Terraform organization name from Step 1 |
| `TF_WORKSPACE` | (Optional) Default workspace name if the workflow pins one |

### Option A — GitHub UI

1. Open the repository → **Settings** → **Secrets and variables** →
   **Actions** → **New repository secret**.
2. Add each secret from the table above.

### Option B — `gh` CLI

```bash
gh secret set TF_API_TOKEN          --body "<paste-token>"
gh secret set TF_CLOUD_ORGANIZATION --body "cloud-champion-bootcamp"
gh secret set TF_WORKSPACE          --body "gcp-bootstrap-dev"
```

Run the commands from the repository root, or pass `--repo <owner>/<repo>`
to target a specific repository.

---

## 7. Verify the Setup

1. Trigger the Terraform GitHub Actions workflow (manually via
   `workflow_dispatch` or by opening a pull request).
2. In HCP Terraform, open the workspace → **Runs** and confirm a new run
   appears and reaches **Plan finished** successfully.
3. If the run fails with an authentication error, regenerate `TF_API_TOKEN`
   and re-check the `TF_CLOUD_ORGANIZATION` value.

## Troubleshooting

- **OAuth callback mismatch** — The callback URL in the GitHub OAuth app must
  exactly match the one shown by HCP Terraform (including the organization
  slug). Update the GitHub app if you rename the HCP organization.
- **401 Unauthorized from GitHub Actions** — The `TF_API_TOKEN` has expired or
  was revoked. Create a new token in HCP Terraform and update the secret.
- **VCS provider shows "Not connected"** — Re-authorize the OAuth app from
  HCP Terraform; users who installed the app may have left the GitHub org.
