#!/bin/bash
# =============================================================================
# GCP GitHub Actions Environment Variables Retrieval Script
# =============================================================================
# Usage: ./get_github_cicd_vars.sh <project-name>
# Example: ./get_github_cicd_vars.sh myapp
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# COLORS FOR OUTPUT
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; exit 1; }
log_section() { echo -e "\n${CYAN}============================================================${NC}";
                echo -e "${CYAN} $1${NC}";
                echo -e "${CYAN}============================================================${NC}"; }

# -----------------------------------------------------------------------------
# VALIDATE INPUT
# -----------------------------------------------------------------------------
if [ $# -ne 1 ]; then
  echo -e "${RED}Usage: $0 <project-name>${NC}"
  echo -e "Example: $0 myapp"
  exit 1
fi

PROJECT_NAME=$1

# -----------------------------------------------------------------------------
# PRE-FLIGHT CHECKS
# -----------------------------------------------------------------------------
log_section "PRE-FLIGHT CHECKS"

# Check gcloud is installed
command -v gcloud &>/dev/null || log_error "gcloud CLI is not installed."
log_success "gcloud CLI found."

# Check logged in account
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
[ -z "$ACTIVE_ACCOUNT" ] && log_error "No active gcloud account. Run: gcloud auth login"
log_success "Active account: $ACTIVE_ACCOUNT"

# Fix project if set to a number
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [[ "$CURRENT_PROJECT" =~ ^[0-9]+$ ]]; then
  log_warning "core/project is set to a project number. Attempting to resolve..."
  RESOLVED_PROJECT=$(gcloud projects list --format="value(projectId)" --limit=1 2>/dev/null)
  [ -z "$RESOLVED_PROJECT" ] && log_error "Could not resolve a valid project ID."
  gcloud config set project "$RESOLVED_PROJECT"
  log_success "Project set to: $RESOLVED_PROJECT"
fi

# -----------------------------------------------------------------------------
# RETRIEVE ORGANIZATION ID
# -----------------------------------------------------------------------------
log_section "RETRIEVING ORGANIZATION DETAILS"

ORG_ID=$(gcloud organizations list \
  --format="value(name)" 2>/dev/null | sed 's/organizations\///' | head -1)
[ -z "$ORG_ID" ] && log_error "Could not retrieve Organization ID."
log_success "Organization ID found: $ORG_ID"

ORG_NAME=$(gcloud organizations list \
  --format="value(displayName)" 2>/dev/null | head -1)
log_success "Organization Name found: $ORG_NAME"

# -----------------------------------------------------------------------------
# RETRIEVE FOLDER DETAILS
# -----------------------------------------------------------------------------
log_section "RETRIEVING FOLDER DETAILS"

FOLDER_NAME="fld-platform-shared"

FOLDER_RESOURCE=$(gcloud resource-manager folders list \
  --organization=$ORG_ID \
  --filter="displayName=$FOLDER_NAME" \
  --format="value(name)" 2>/dev/null | head -1)

if [ -z "$FOLDER_RESOURCE" ]; then
  log_warning "Folder '$FOLDER_NAME' not found under organization $ORG_ID."
  FOLDER_ID="NOT_FOUND"
else
  FOLDER_ID=$(echo $FOLDER_RESOURCE | sed 's/folders\///')
  log_success "Folder ID found: $FOLDER_ID"
fi

# -----------------------------------------------------------------------------
# RETRIEVE PROJECT DETAILS
# -----------------------------------------------------------------------------
log_section "RETRIEVING PROJECT DETAILS"

# Search project by name pattern inside folder
if [ "$FOLDER_ID" != "NOT_FOUND" ]; then
  PROJECT_ID=$(gcloud projects list \
    --filter="parent.id=$FOLDER_ID parent.type=folder name:${PROJECT_NAME}*" \
    --format="value(projectId)" 2>/dev/null | head -1)
else
  # Fallback: search across the org
  PROJECT_ID=$(gcloud projects list \
    --filter="name:${PROJECT_NAME}*" \
    --format="value(projectId)" 2>/dev/null | head -1)
fi

if [ -z "$PROJECT_ID" ]; then
  log_warning "No project matching '${PROJECT_NAME}*' found."
  PROJECT_ID="NOT_FOUND"
  PROJECT_NUMBER="NOT_FOUND"
else
  log_success "Project ID found: $PROJECT_ID"
  PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID \
    --format="value(projectNumber)" 2>/dev/null)
  log_success "Project Number found: $PROJECT_NUMBER"
fi

# -----------------------------------------------------------------------------
# RETRIEVE BILLING ACCOUNT
# -----------------------------------------------------------------------------
log_section "RETRIEVING BILLING DETAILS"

if [ "$PROJECT_ID" != "NOT_FOUND" ]; then
  BILLING_ACCOUNT=$(gcloud billing projects describe $PROJECT_ID \
    --format="value(billingAccountName)" 2>/dev/null | sed 's/billingAccounts\///')

  if [ -z "$BILLING_ACCOUNT" ]; then
    log_warning "No billing account linked to $PROJECT_ID. Attempting to link now..."

    # Retrieve the first available active billing account
    AVAILABLE_BILLING=$(gcloud billing accounts list \
      --filter="open=true" \
      --format="value(name)" 2>/dev/null | sed 's/billingAccounts\///' | head -1)

    if [ -n "$AVAILABLE_BILLING" ]; then
      if gcloud billing projects link $PROJECT_ID \
        --billing-account=$AVAILABLE_BILLING 2>/dev/null; then
        BILLING_ACCOUNT=$AVAILABLE_BILLING
        log_success "Billing account linked successfully: $BILLING_ACCOUNT"
      else
        BILLING_ACCOUNT="NOT_LINKED"
        log_warning "Could not link billing account. Check billing permissions."
        log_warning "Run manually: gcloud billing projects link $PROJECT_ID --billing-account=<BILLING_ACCOUNT_ID>"
      fi
    else
      BILLING_ACCOUNT="NOT_LINKED"
      log_warning "No active billing accounts found in your organization."
      log_warning "Run manually: gcloud billing accounts list"
    fi
  else
    log_success "Billing Account found: $BILLING_ACCOUNT"
  fi
else
  BILLING_ACCOUNT="NOT_FOUND"
  log_warning "Skipping billing retrieval — project not found."
fi

# -----------------------------------------------------------------------------
# RETRIEVE SERVICE ACCOUNT DETAILS
# -----------------------------------------------------------------------------
log_section "RETRIEVING SERVICE ACCOUNT DETAILS"

SA_NAME="sa-github-terraform"

if [ "$PROJECT_ID" != "NOT_FOUND" ]; then
  SA_EMAIL=$(gcloud iam service-accounts list \
    --project=$PROJECT_ID \
    --filter="email:${SA_NAME}@*" \
    --format="value(email)" 2>/dev/null | head -1)

  if [ -z "$SA_EMAIL" ]; then
    log_warning "Service account '$SA_NAME' not found in project $PROJECT_ID."
    SA_EMAIL="NOT_FOUND"
    SA_UNIQUE_ID="NOT_FOUND"
  else
    log_success "Service Account found: $SA_EMAIL"
    SA_UNIQUE_ID=$(gcloud iam service-accounts describe $SA_EMAIL \
      --project=$PROJECT_ID \
      --format="value(uniqueId)" 2>/dev/null)
    log_success "Service Account Unique ID: $SA_UNIQUE_ID"
  fi
else
  SA_EMAIL="NOT_FOUND"
  SA_UNIQUE_ID="NOT_FOUND"
  log_warning "Skipping service account retrieval — project not found."
fi

# -----------------------------------------------------------------------------
# RETRIEVE SERVICE ACCOUNT KEY FROM SECRET MANAGER
# -----------------------------------------------------------------------------
log_section "RETRIEVING SERVICE ACCOUNT KEY"

SECRET_NAME="github-cicd-sa-key-${PROJECT_NAME}"
SA_KEY_FILE="${SA_NAME}-key.json"
SA_KEY_CONTENT="NOT_FOUND"

if [ "$PROJECT_ID" != "NOT_FOUND" ]; then

  # Step 1 — Enable Secret Manager API if not already enabled
  SM_API_ENABLED=$(gcloud services list \
    --project=$PROJECT_ID \
    --filter="name:secretmanager.googleapis.com" \
    --format="value(state)" 2>/dev/null)

  if [ "$SM_API_ENABLED" != "ENABLED" ]; then
    log_info "Secret Manager API not enabled. Enabling now..."
    if gcloud services enable secretmanager.googleapis.com       --project=$PROJECT_ID 2>/dev/null; then
      log_success "Secret Manager API enabled."
      SM_API_ENABLED="ENABLED"
    else
      log_warning "Could not enable Secret Manager API. Skipping secret retrieval."
      SM_API_ENABLED="DISABLED"
    fi
  fi

  # Step 2 — Check Secret Manager for existing key
  if [ "$SM_API_ENABLED" = "ENABLED" ]; then
    log_info "Checking Secret Manager for existing key..."
    SECRET_EXISTS=$(timeout 10 gcloud secrets list \
      --project=$PROJECT_ID \
      --filter="name:$SECRET_NAME" \
      --format="value(name)" 2>/dev/null | head -1)

    if [ -n "$SECRET_EXISTS" ]; then
      SA_KEY_CONTENT=$(timeout 10 gcloud secrets versions access latest \
        --secret=$SECRET_NAME \
        --project=$PROJECT_ID 2>/dev/null)
      [ -n "$SA_KEY_CONTENT" ] \
        && log_success "SA Key retrieved from Secret Manager: $SECRET_NAME" \
        || log_warning "Secret found but could not retrieve contents."
    else
      log_warning "Secret '$SECRET_NAME' not found in Secret Manager."
    fi
  fi

  # Step 3 — Generate a new key if not retrieved from Secret Manager
  if [ "$SA_KEY_CONTENT" = "NOT_FOUND" ] && [ "$SA_EMAIL" != "NOT_FOUND" ]; then
    log_info "Generating a new SA key file..."

    # Ensure serviceAccountKeyAdmin role is granted
    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="user:$(gcloud config get-value account 2>/dev/null)" \
      --role="roles/iam.serviceAccountKeyAdmin" \
      --quiet 2>/dev/null || true

    # Generate the key
    if timeout 30 gcloud iam service-accounts keys create $SA_KEY_FILE \
      --iam-account=$SA_EMAIL \
      --project=$PROJECT_ID; then
      SA_KEY_CONTENT=$(cat $SA_KEY_FILE)
      log_success "New SA key generated and saved to: $SA_KEY_FILE"

      # Step 4 — Store the new key in Secret Manager
      log_info "Storing SA key in Secret Manager..."
      gcloud secrets create $SECRET_NAME \
        --replication-policy="automatic" \
        --project=$PROJECT_ID 2>/dev/null || true
      gcloud secrets versions add $SECRET_NAME \
        --data-file=$SA_KEY_FILE \
        --project=$PROJECT_ID 2>/dev/null \
        && log_success "SA key stored in Secret Manager as: $SECRET_NAME" \
        || log_warning "Could not store key in Secret Manager."
    else
      log_warning "Could not generate SA key. Verify the following:"
      log_warning "  1. SA exists       : gcloud iam service-accounts list --project=$PROJECT_ID"
      log_warning "  2. Key Admin role  : gcloud projects get-iam-policy $PROJECT_ID --flatten=bindings[].members --filter=bindings.members:$(gcloud config get-value account 2>/dev/null)"
    fi
  fi

else
  log_warning "Skipping SA key retrieval — project not found."
fi

# -----------------------------------------------------------------------------
# RETRIEVE WORKLOAD IDENTITY (if configured)
# -----------------------------------------------------------------------------
log_section "RETRIEVING WORKLOAD IDENTITY DETAILS"

WI_POOL_ID="NOT_CONFIGURED"
WI_PROVIDER_ID="NOT_CONFIGURED"
WI_PROVIDER_FULL="NOT_CONFIGURED"

if [ "$PROJECT_ID" != "NOT_FOUND" ]; then
  WI_POOL=$(gcloud iam workload-identity-pools list \
    --project=$PROJECT_ID \
    --location=global \
    --format="value(name)" 2>/dev/null | head -1)

  if [ -n "$WI_POOL" ]; then
    WI_POOL_ID=$(echo $WI_POOL | awk -F'/' '{print $NF}')
    log_success "Workload Identity Pool found: $WI_POOL_ID"

    WI_PROVIDER=$(gcloud iam workload-identity-pools providers list \
      --workload-identity-pool=$WI_POOL_ID \
      --project=$PROJECT_ID \
      --location=global \
      --format="value(name)" 2>/dev/null | head -1)

    if [ -n "$WI_PROVIDER" ]; then
      WI_PROVIDER_ID=$(echo $WI_PROVIDER | awk -F'/' '{print $NF}')
      log_success "Workload Identity Provider found: $WI_PROVIDER_ID"
      # Construct full Workload Identity Provider resource name
      WI_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WI_POOL_ID}/providers/${WI_PROVIDER_ID}"
      log_success "Workload Identity Provider full path: $WI_PROVIDER_FULL"
    fi
  else
    log_warning "No Workload Identity Pool configured for this project."
  fi
fi

# -----------------------------------------------------------------------------
# RETRIEVE ARTIFACT REGISTRY DETAILS (if configured)
# -----------------------------------------------------------------------------
log_section "RETRIEVING ARTIFACT REGISTRY DETAILS"

AR_REPO="NOT_CONFIGURED"
AR_LOCATION="NOT_CONFIGURED"

if [ "$PROJECT_ID" != "NOT_FOUND" ]; then
  AR_API_ENABLED=$(gcloud services list \
    --project=$PROJECT_ID \
    --filter="name:artifactregistry.googleapis.com" \
    --format="value(state)" 2>/dev/null)

  if [ "$AR_API_ENABLED" = "ENABLED" ]; then
    AR_OUTPUT=$(timeout 15 gcloud artifacts repositories list \
      --project=$PROJECT_ID \
      --format="value(name,location)" 2>/dev/null | head -1)

    if [ -n "$AR_OUTPUT" ]; then
      AR_REPO=$(echo $AR_OUTPUT | awk '{print $1}' | awk -F'/' '{print $NF}')
      AR_LOCATION=$(echo $AR_OUTPUT | awk '{print $2}')
      log_success "Artifact Registry found: $AR_REPO (Location: $AR_LOCATION)"
    else
      log_warning "No Artifact Registry repository found."
    fi
  else
    log_warning "Artifact Registry API not enabled. Skipping."
  fi
fi

# -----------------------------------------------------------------------------
# RETRIEVE GKE CLUSTER DETAILS (if configured)
# -----------------------------------------------------------------------------
log_section "RETRIEVING GKE CLUSTER DETAILS"

GKE_CLUSTER="NOT_CONFIGURED"
GKE_ZONE="NOT_CONFIGURED"
GKE_REGION="NOT_CONFIGURED"

if [ "$PROJECT_ID" != "NOT_FOUND" ]; then
  GKE_API_ENABLED=$(gcloud services list \
    --project=$PROJECT_ID \
    --filter="name:container.googleapis.com" \
    --format="value(state)" 2>/dev/null)

  if [ "$GKE_API_ENABLED" = "ENABLED" ]; then
    GKE_OUTPUT=$(timeout 15 gcloud container clusters list \
      --project=$PROJECT_ID \
      --format="value(name,zone,location)" 2>/dev/null | head -1)

    if [ -n "$GKE_OUTPUT" ]; then
      GKE_CLUSTER=$(echo $GKE_OUTPUT | awk '{print $1}')
      GKE_ZONE=$(echo $GKE_OUTPUT    | awk '{print $2}')
      GKE_REGION=$(echo $GKE_OUTPUT  | awk '{print $3}')
      log_success "GKE Cluster found: $GKE_CLUSTER (Zone: $GKE_ZONE)"
    else
      log_warning "No GKE cluster found."
    fi
  else
    log_warning "GKE API not enabled. Skipping."
  fi
fi

# -----------------------------------------------------------------------------
# OUTPUT — GITHUB ACTIONS SECRETS & VARIABLES
# -----------------------------------------------------------------------------
log_section "GITHUB ACTIONS — SECRETS & VARIABLES"

echo ""
echo -e "${YELLOW}--------------------------------------------------------------${NC}"
echo -e "${YELLOW} Add the following as GitHub Actions SECRETS${NC}"
echo -e "${YELLOW} (Settings → Secrets → Actions → New repository secret)${NC}"
echo -e "${YELLOW}--------------------------------------------------------------${NC}"
echo ""
echo -e "  ${CYAN}Secret Name         :${NC} GCP_SA_KEY"
echo -e "  ${CYAN}Secret Value        :${NC} (contents of $SA_KEY_CONTENT)"
echo ""
echo -e "${YELLOW}--------------------------------------------------------------${NC}"
echo -e "${YELLOW} Add the following as GitHub Actions VARIABLES${NC}"
echo -e "${YELLOW} (Settings → Secrets → Actions → Variables tab)${NC}"
echo -e "${YELLOW}--------------------------------------------------------------${NC}"
echo ""
echo -e "  ${GREEN}GCP_ORG_ID          :${NC} $ORG_ID"
echo -e "  ${GREEN}GCP_ORG_NAME        :${NC} $ORG_NAME"
echo -e "  ${GREEN}GCP_FOLDER_ID       :${NC} $FOLDER_ID"
echo -e "  ${GREEN}GCP_PROJECT_ID      :${NC} $PROJECT_ID"
echo -e "  ${GREEN}GCP_PROJECT_NUMBER  :${NC} $PROJECT_NUMBER"
echo -e "  ${GREEN}GCP_SA_EMAIL        :${NC} $SA_EMAIL"
echo -e "  ${GREEN}GCP_SA_UNIQUE_ID    :${NC} $SA_UNIQUE_ID"
echo -e "  ${GREEN}GCP_BILLING_ACCOUNT :${NC} $BILLING_ACCOUNT"
echo -e "  ${GREEN}GCP_AR_REPO         :${NC} $AR_REPO"
echo -e "  ${GREEN}GCP_AR_LOCATION     :${NC} $AR_LOCATION"
echo -e "  ${GREEN}GCP_GKE_CLUSTER     :${NC} $GKE_CLUSTER"
echo -e "  ${GREEN}GCP_GKE_ZONE        :${NC} $GKE_ZONE"
echo -e "  ${GREEN}GCP_GKE_REGION      :${NC} $GKE_REGION"
echo -e "  ${GREEN}GCP_WI_POOL_ID              :${NC} $WI_POOL_ID"
echo -e "  ${GREEN}GCP_WI_PROVIDER_ID          :${NC} $WI_PROVIDER_ID"
echo -e "  ${GREEN}GCP_WORKLOAD_IDENTITY_PROVIDER :${NC} $WI_PROVIDER_FULL"

# -----------------------------------------------------------------------------
# OUTPUT — GITHUB ACTIONS WORKFLOW SNIPPET
# -----------------------------------------------------------------------------
log_section "SAMPLE GITHUB ACTIONS WORKFLOW SNIPPET"

cat <<EOF

name: Deploy to GCP

on:
  push:
    branches: [main]

env:
  GCP_PROJECT_ID     : \${{ vars.GCP_PROJECT_ID }}
  GCP_SA_EMAIL       : \${{ vars.GCP_SA_EMAIL }}
  GCP_AR_REPO        : \${{ vars.GCP_AR_REPO }}
  GCP_AR_LOCATION    : \${{ vars.GCP_AR_LOCATION }}
  GCP_GKE_CLUSTER    : \${{ vars.GCP_GKE_CLUSTER }}
  GCP_GKE_ZONE       : \${{ vars.GCP_GKE_ZONE }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          credentials_json: \${{ secrets.GCP_SA_KEY }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2
        with:
          project_id: \${{ vars.GCP_PROJECT_ID }}

      - name: Configure Docker for Artifact Registry
        run: |
          gcloud auth configure-docker \${{ vars.GCP_AR_LOCATION }}-docker.pkg.dev

      - name: Build and Push Docker Image
        run: |
          docker build -t \${{ vars.GCP_AR_LOCATION }}-docker.pkg.dev/\${{ vars.GCP_PROJECT_ID }}/\${{ vars.GCP_AR_REPO }}/app:latest .
          docker push \${{ vars.GCP_AR_LOCATION }}-docker.pkg.dev/\${{ vars.GCP_PROJECT_ID }}/\${{ vars.GCP_AR_REPO }}/app:latest

      - name: Deploy to GKE
        run: |
          gcloud container clusters get-credentials \${{ vars.GCP_GKE_CLUSTER }} --zone \${{ vars.GCP_GKE_ZONE }}
          kubectl apply -f k8s/
EOF

echo ""
echo -e "${YELLOW}============================================================${NC}"
echo -e "${GREEN} Variable retrieval completed successfully!${NC}"
echo -e "${YELLOW}============================================================${NC}"