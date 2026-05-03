resource "azurerm_data_factory" "adf" {
  name                = "adf-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ── Key Vault access policy for ADF managed identity ──────────────────────────
resource "azurerm_key_vault_access_policy" "adf" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_data_factory.adf.identity[0].tenant_id
  object_id    = azurerm_data_factory.adf.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# ── Linked Services ────────────────────────────────────────────────────────────
resource "azurerm_data_factory_linked_service_key_vault" "kv" {
  name            = "ls_KeyVault"
  data_factory_id = azurerm_data_factory.adf.id
  key_vault_id    = var.key_vault_id
}

resource "azurerm_data_factory_linked_service_azure_blob_storage" "adls" {
  name            = "ls_ADLS"
  data_factory_id = azurerm_data_factory.adf.id

  # Use Key Vault reference for the connection string
  connection_string_insecure = "DefaultEndpointsProtocol=https;AccountName=${var.adls_account_name};EndpointSuffix=core.windows.net"
}

resource "azurerm_data_factory_linked_service_azure_databricks" "dbw" {
  name            = "ls_Databricks"
  data_factory_id = azurerm_data_factory.adf.id
  adb_domain      = var.databricks_workspace_url

  msi_work_space_resource_id = var.databricks_workspace_resource_id

  existing_cluster_id = var.databricks_cluster_id
}

# ── Datasets ───────────────────────────────────────────────────────────────────
resource "azurerm_data_factory_dataset_parquet" "bronze_raw" {
  name                = "ds_Bronze_Raw"
  data_factory_id     = azurerm_data_factory.adf.id
  linked_service_name = azurerm_data_factory_linked_service_azure_blob_storage.adls.name

  azure_blob_storage_location {
    container = "bronze"
    path      = "raw"
    filename  = "@dataset().fileName"
  }
}

# ── Pipeline: Ingest → Bronze ──────────────────────────────────────────────────
resource "azurerm_data_factory_pipeline" "ingest_bronze" {
  name            = "pl_Ingest_Bronze"
  data_factory_id = azurerm_data_factory.adf.id
  description     = "Copies source data into the Bronze layer (raw landing zone)"

  parameters = {
    sourceContainer = "string"
    sourcePath      = "string"
    fileName        = "string"
  }

  activities_json = jsonencode([
    {
      name = "Copy_To_Bronze"
      type = "Copy"
      inputs = [{
        referenceName = azurerm_data_factory_dataset_parquet.bronze_raw.name
        type          = "DatasetReference"
        parameters    = { fileName = "@pipeline().parameters.fileName" }
      }]
      outputs = [{
        referenceName = azurerm_data_factory_dataset_parquet.bronze_raw.name
        type          = "DatasetReference"
        parameters    = { fileName = "@pipeline().parameters.fileName" }
      }]
      typeProperties = {
        source = { type = "ParquetSource" }
        sink   = { type = "ParquetSink" }
      }
    }
  ])
}

# ── Pipeline: Orchestrate Lakehouse (trigger Databricks notebooks) ─────────────
resource "azurerm_data_factory_pipeline" "orchestrate" {
  name            = "pl_Orchestrate_Lakehouse"
  data_factory_id = azurerm_data_factory.adf.id
  description     = "Orchestrates Bronze → Silver → Gold Databricks notebook chain"

  activities_json = jsonencode([
    {
      name = "nb_Bronze_Ingest"
      type = "DatabricksNotebook"
      linkedServiceName = {
        referenceName = azurerm_data_factory_linked_service_azure_databricks.dbw.name
        type          = "LinkedServiceReference"
      }
      typeProperties = {
        notebookPath = "/Shared/lakehouse/bronze/ingest_raw"
      }
      dependsOn = []
    },
    {
      name = "nb_Silver_Transform"
      type = "DatabricksNotebook"
      linkedServiceName = {
        referenceName = azurerm_data_factory_linked_service_azure_databricks.dbw.name
        type          = "LinkedServiceReference"
      }
      typeProperties = {
        notebookPath = "/Shared/lakehouse/silver/transform_cleanse"
      }
      dependsOn = [{
        activity           = "nb_Bronze_Ingest"
        dependencyConditions = ["Succeeded"]
      }]
    },
    {
      name = "nb_Gold_Aggregate"
      type = "DatabricksNotebook"
      linkedServiceName = {
        referenceName = azurerm_data_factory_linked_service_azure_databricks.dbw.name
        type          = "LinkedServiceReference"
      }
      typeProperties = {
        notebookPath = "/Shared/lakehouse/gold/aggregate_serve"
      }
      dependsOn = [{
        activity           = "nb_Silver_Transform"
        dependencyConditions = ["Succeeded"]
      }]
    }
  ])
}

# ── Trigger: daily at 02:00 UTC ────────────────────────────────────────────────
resource "azurerm_data_factory_trigger_schedule" "daily" {
  name            = "trg_Daily_0200"
  data_factory_id = azurerm_data_factory.adf.id
  pipeline_name   = azurerm_data_factory_pipeline.orchestrate.name

  interval  = 1
  frequency = "Day"
  start_time = "2024-01-01T02:00:00Z"
}
