subscription_id = "00000000-0000-0000-0000-000000000000"  # replace
environment     = "prod"
location        = "eastus2"
project         = "lhouse"

databricks_sku                     = "premium"
databricks_cluster_node_type       = "Standard_DS4_v2"
databricks_spark_version           = "13.3.x-scala2.12"
databricks_autotermination_minutes = 20

adls_replication_type = "GRS"

tags = {
  cost_center = "engineering"
  owner       = "data-platform-team"
}
