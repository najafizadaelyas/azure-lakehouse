# ── Workspace ──────────────────────────────────────────────────────────────────
resource "azurerm_databricks_workspace" "ws" {
  name                = "dbw-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  managed_resource_group_name = "rg-${var.name_prefix}-dbw-managed"

  tags = var.tags
}

# ── Cluster ────────────────────────────────────────────────────────────────────
resource "databricks_cluster" "main" {
  cluster_name            = "lhouse-${var.name_prefix}"
  spark_version           = var.spark_version
  node_type_id            = var.cluster_node_type
  autotermination_minutes = var.autotermination_minutes

  autoscale {
    min_workers = 1
    max_workers = 4
  }

  spark_conf = {
    "spark.databricks.delta.preview.enabled"         = "true"
    "spark.databricks.io.cache.enabled"              = "true"
    "spark.databricks.delta.optimizeWrite.enabled"   = "true"
    "spark.databricks.delta.autoCompact.enabled"     = "true"
    # ADLS Gen2 access via storage account key (from Key Vault)
    "fs.azure.account.auth.type.${var.adls_account_name}.dfs.core.windows.net"      = "SharedKey"
    "fs.azure.account.key.${var.adls_account_name}.dfs.core.windows.net"            = "{{secrets/lakehouse-scope/adls-primary-access-key}}"
  }

  library {
    pypi {
      package = "delta-spark==3.0.0"
    }
  }

  library {
    pypi {
      package = "azure-storage-file-datalake==12.14.0"
    }
  }
}

# ── Secret scope (backed by Azure Key Vault) ────────────────────────────────────
resource "databricks_secret_scope" "kv" {
  name = "lakehouse-scope"

  keyvault_metadata {
    resource_id = var.key_vault_id
    dns_name    = var.key_vault_uri
  }
}
