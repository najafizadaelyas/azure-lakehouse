# Databricks notebook: Bronze — Raw Ingestion
# Reads source files from the landing zone and writes them to the Bronze Delta table.
# Supports Parquet, CSV, and JSON source formats.

import re
from pyspark.sql import SparkSession
from pyspark.sql.functions import current_timestamp, lit, input_file_name

# ── Parameters (overridden by ADF / Databricks job widgets) ───────────────────
dbutils.widgets.text("source_container",  "landing",   "Source container")
dbutils.widgets.text("source_path",       "sales/",    "Source path")
dbutils.widgets.text("source_format",     "parquet",   "Source format")
dbutils.widgets.text("bronze_table",      "sales_raw", "Bronze table name")
dbutils.widgets.text("adls_account",      "",          "ADLS account name")

SOURCE_CONTAINER = dbutils.widgets.get("source_container")
SOURCE_PATH      = dbutils.widgets.get("source_path")
SOURCE_FORMAT    = dbutils.widgets.get("source_format")
BRONZE_TABLE     = dbutils.widgets.get("bronze_table")
ADLS_ACCOUNT     = dbutils.widgets.get("adls_account")

BRONZE_PATH      = f"abfss://bronze@{ADLS_ACCOUNT}.dfs.core.windows.net/{BRONZE_TABLE}"
CHECKPOINT_PATH  = f"abfss://checkpoints@{ADLS_ACCOUNT}.dfs.core.windows.net/bronze/{BRONZE_TABLE}"

spark: SparkSession = spark  # injected by Databricks runtime

# ── Ingest ─────────────────────────────────────────────────────────────────────
source_uri = f"abfss://{SOURCE_CONTAINER}@{ADLS_ACCOUNT}.dfs.core.windows.net/{SOURCE_PATH}"

print(f"[bronze] Reading {SOURCE_FORMAT} from {source_uri}")

reader_options = {"mergeSchema": "true"}
if SOURCE_FORMAT == "csv":
    reader_options.update({"header": "true", "inferSchema": "true"})

raw_df = (
    spark.read
    .format(SOURCE_FORMAT)
    .options(**reader_options)
    .load(source_uri)
    .withColumn("_ingested_at",  current_timestamp())
    .withColumn("_source_file",  input_file_name())
    .withColumn("_source_path",  lit(source_uri))
)

print(f"[bronze] Schema:\n{raw_df.printSchema()}")
print(f"[bronze] Row count: {raw_df.count():,}")

# ── Write Delta (append-only; idempotent via MERGE in silver) ─────────────────
(
    raw_df.write
    .format("delta")
    .mode("append")
    .option("mergeSchema", "true")
    .save(BRONZE_PATH)
)

# Register in Unity Catalog / Hive metastore
spark.sql(f"""
    CREATE TABLE IF NOT EXISTS bronze.{BRONZE_TABLE}
    USING DELTA
    LOCATION '{BRONZE_PATH}'
""")

print(f"[bronze] Written to {BRONZE_PATH}")

# ── Optimize ───────────────────────────────────────────────────────────────────
spark.sql(f"OPTIMIZE bronze.{BRONZE_TABLE}")
print("[bronze] OPTIMIZE complete")
