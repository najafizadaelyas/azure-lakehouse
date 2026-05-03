#!/usr/bin/env bash
# setup_databricks.sh — idempotent Databricks workspace bootstrap.
# Creates secret scope, uploads init script, imports notebooks, and creates job.

set -euo pipefail

: "${DATABRICKS_HOST:?Set DATABRICKS_HOST}"
: "${DATABRICKS_TOKEN:?Set DATABRICKS_TOKEN}"
: "${ADLS_ACCOUNT_NAME:?Set ADLS_ACCOUNT_NAME}"
: "${KEY_VAULT_URI:?Set KEY_VAULT_URI}"
: "${KEY_VAULT_RESOURCE_ID:?Set KEY_VAULT_RESOURCE_ID}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ── Secret scope (backed by Key Vault) ────────────────────────────────────────
echo "==> Creating/updating secret scope..."
databricks secrets create-scope \
  --scope lakehouse-scope \
  --scope-backend-type AZURE_KEYVAULT \
  --resource-id "$KEY_VAULT_RESOURCE_ID" \
  --dns-name "$KEY_VAULT_URI" 2>/dev/null || echo "   scope already exists, skipping"

# ── Init script ────────────────────────────────────────────────────────────────
echo "==> Uploading cluster init script..."
DBFS_INIT_PATH="dbfs:/FileStore/lakehouse/init/install_libs.sh"
databricks fs cp --overwrite \
  "$REPO_ROOT/databricks/init_scripts/install_libs.sh" \
  "$DBFS_INIT_PATH"

# ── Notebooks ──────────────────────────────────────────────────────────────────
echo "==> Importing notebooks..."
databricks workspace mkdirs /Shared/lakehouse
databricks workspace import_dir "$REPO_ROOT/databricks/notebooks" \
  /Shared/lakehouse --overwrite --exclude-hidden-files

# ── Job ────────────────────────────────────────────────────────────────────────
echo "==> Creating/updating Databricks job..."
JOB_JSON=$(cat "$REPO_ROOT/databricks/jobs/lakehouse_job.json" | \
  sed "s|<ADLS_ACCOUNT>|$ADLS_ACCOUNT_NAME|g")

EXISTING_JOB_ID=$(databricks jobs list --output JSON 2>/dev/null | \
  python3 -c "
import sys, json
jobs = json.load(sys.stdin).get('jobs', [])
match = [j for j in jobs if j['settings']['name'] == 'lakehouse-daily-etl']
print(match[0]['job_id'] if match else '')
")

if [[ -n "$EXISTING_JOB_ID" ]]; then
  echo "   updating job $EXISTING_JOB_ID..."
  echo "$JOB_JSON" | databricks jobs reset --job-id "$EXISTING_JOB_ID" --json -
else
  echo "   creating new job..."
  echo "$JOB_JSON" | databricks jobs create --json -
fi

echo "==> Databricks workspace setup complete."
