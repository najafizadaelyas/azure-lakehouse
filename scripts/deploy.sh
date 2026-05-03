#!/usr/bin/env bash
# deploy.sh — local bootstrap for the Azure Lakehouse
# Usage: ./scripts/deploy.sh [dev|prod]

set -euo pipefail

ENV="${1:-dev}"
TF_DIR="$(dirname "$0")/../terraform"

echo "==> Deploying lakehouse (environment: $ENV)"

# ── Pre-flight checks ──────────────────────────────────────────────────────────
for cmd in terraform az databricks; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' not found. Install it and re-run." >&2
    exit 1
  fi
done

echo "==> Logging in to Azure..."
az account show &>/dev/null || az login --use-device-code

# ── Terraform ─────────────────────────────────────────────────────────────────
echo "==> Terraform init..."
terraform -chdir="$TF_DIR" init

echo "==> Terraform plan ($ENV)..."
terraform -chdir="$TF_DIR" plan \
  -var-file="environments/${ENV}.tfvars" \
  -out="${ENV}.tfplan"

read -r -p "Apply the plan? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  terraform -chdir="$TF_DIR" apply "${ENV}.tfplan"
  echo "==> Infrastructure deployed."
else
  echo "==> Aborted."
  exit 0
fi

# ── Databricks notebooks ───────────────────────────────────────────────────────
DATABRICKS_HOST=$(terraform -chdir="$TF_DIR" output -raw databricks_workspace_url)
export DATABRICKS_HOST

echo "==> Configuring Databricks CLI..."
databricks configure --token  # prompts for PAT

echo "==> Uploading notebooks..."
databricks workspace import_dir "$(dirname "$0")/../databricks/notebooks" \
  /Shared/lakehouse --overwrite --exclude-hidden-files

echo "==> Done. Lakehouse ready at $DATABRICKS_HOST"
