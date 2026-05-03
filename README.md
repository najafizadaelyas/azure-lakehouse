# azure-lakehouse

Cloud lakehouse architecture on Azure, fully provisioned with Terraform.

```
Azure Data Lake Storage Gen2 (bronze / silver / gold)
        ↑  copy          ↓  trigger notebooks
Azure Data Factory  ──────►  Azure Databricks
        │                          │
        └──── Key Vault secrets ───┘
```

## Stack

| Layer | Technology |
|-------|-----------|
| Storage | ADLS Gen2 — hierarchical namespace |
| Compute | Azure Databricks (Premium, autoscaling cluster) |
| Orchestration | Azure Data Factory — scheduled pipeline |
| Format | Delta Lake (ACID, time-travel, Z-ORDER) |
| Secrets | Azure Key Vault (scope mounted in Databricks) |
| IaC | Terraform ≥ 1.5 |
| CI/CD | GitHub Actions (OIDC, no stored credentials) |

## Medallion architecture

```
landing/   →   bronze/   →   silver/   →   gold/
raw files      Delta raw     cleansed       aggregated
(parquet/csv)  append-only   upsert MERGE   BI-ready
```

- **Bronze** — raw ingestion, schema-on-read, `_ingested_at` watermark
- **Silver** — dedup, type casting, null removal, MERGE upsert
- **Gold** — business aggregates, Z-ORDER optimised, partitioned by year/month

## Repository layout

```
azure-lakehouse/
├── terraform/
│   ├── main.tf                  # root module
│   ├── providers.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── environments/
│   │   ├── dev.tfvars
│   │   └── prod.tfvars
│   └── modules/
│       ├── storage/             # ADLS Gen2 + containers
│       ├── key_vault/           # Key Vault + secrets
│       ├── databricks/          # Workspace + cluster + secret scope
│       └── data_factory/        # ADF + linked services + pipelines + trigger
├── databricks/
│   ├── notebooks/
│   │   ├── bronze/ingest_raw.py
│   │   ├── silver/transform_cleanse.py
│   │   ├── gold/aggregate_serve.py
│   │   └── utils/delta_helpers.py
│   ├── jobs/lakehouse_job.json  # Databricks job definition
│   └── init_scripts/install_libs.sh
├── scripts/
│   ├── deploy.sh                # local bootstrap
│   └── setup_databricks.sh     # idempotent workspace setup
└── .github/workflows/deploy.yml # CI/CD: plan on PR, apply + notebooks on merge
```

## Quick start

### Prerequisites

- Terraform ≥ 1.5
- Azure CLI (`az login`)
- Databricks CLI (`pip install databricks-cli`)
- An Azure subscription with Owner / Contributor rights

### 1. Provision infrastructure

```bash
cd terraform
cp environments/dev.tfvars environments/dev.local.tfvars
# edit dev.local.tfvars — set subscription_id

terraform init
terraform apply -var-file="environments/dev.local.tfvars"
```

### 2. Bootstrap Databricks workspace

```bash
export DATABRICKS_HOST=$(terraform output -raw databricks_workspace_url)
export DATABRICKS_TOKEN=<your-pat>
export ADLS_ACCOUNT_NAME=$(terraform output -raw adls_account_name)
export KEY_VAULT_URI=$(terraform output -raw key_vault_uri)
export KEY_VAULT_RESOURCE_ID=<key-vault-resource-id>

./scripts/setup_databricks.sh
```

### 3. Trigger a pipeline run

```bash
# via ADF
az datafactory pipeline create-run \
  --resource-group rg-lhouse-dev \
  --factory-name adf-lhouse-dev \
  --name pl_Orchestrate_Lakehouse

# or directly via Databricks job
databricks jobs run-now --job-id <JOB_ID>
```

## CI/CD

| Event | Action |
|-------|--------|
| Pull request to `main` | `terraform plan` output posted as PR comment |
| Push to `main` | `terraform apply` (prod) → deploy notebooks |

Secrets required in GitHub:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Service principal / managed identity client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `DATABRICKS_HOST` | Workspace URL |
| `DATABRICKS_TOKEN` | PAT or AAD token |

## Delta Lake operations

```sql
-- Time travel
SELECT * FROM silver.sales_cleansed VERSION AS OF 5;
SELECT * FROM silver.sales_cleansed TIMESTAMP AS OF '2024-06-01';

-- History
DESCRIBE HISTORY gold.sales_summary_monthly;

-- Compact small files
OPTIMIZE silver.sales_cleansed ZORDER BY (sale_id);

-- Clean up old snapshots
VACUUM silver.sales_cleansed RETAIN 168 HOURS;
```
