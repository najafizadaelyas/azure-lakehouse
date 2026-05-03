subscription_id = "00000000-0000-0000-0000-000000000000"  # replace
environment     = "dev"
location        = "eastus2"
project         = "lhouse"

databricks_sku                     = "premium"
databricks_cluster_node_type       = "Standard_DS3_v2"
databricks_spark_version           = "13.3.x-scala2.12"
databricks_autotermination_minutes = 30

adls_replication_type = "ZRS"

tags = {
  cost_center = "engineering"
  owner       = "data-platform-team"
}
