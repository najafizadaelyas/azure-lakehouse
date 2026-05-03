"""
Local end-to-end lakehouse runner.
Replaces ADLS Gen2 paths with local filesystem paths and
replaces the Databricks dbutils / injected `spark` with a local SparkSession.

Usage:
    py -3.12 local/run_local.py
"""

import os
import sys

# ── Hadoop winutils (required on Windows) ─────────────────────────────────────
_hadoop_home = os.path.join(os.path.expanduser("~"), "hadoop")
_hadoop_bin  = os.path.join(_hadoop_home, "bin")
os.environ["HADOOP_HOME"] = _hadoop_home
os.environ["PATH"] = _hadoop_bin + os.pathsep + os.environ.get("PATH", "")
os.environ["JAVA_TOOL_OPTIONS"] = f"-Djava.library.path={_hadoop_bin}"

# Pass library path AND Delta packages via PYSPARK_SUBMIT_ARGS so spark-submit.cmd
# picks them up before the JVM is launched (configure_spark_with_delta_pip would
# overwrite this, so we set it manually and skip that helper).
_delta_pkg = "io.delta:delta-spark_2.12:3.2.0"
os.environ["PYSPARK_SUBMIT_ARGS"] = (
    f"--conf spark.driver.extraLibraryPath={_hadoop_bin} "
    f"--packages {_delta_pkg} "
    "pyspark-shell"
)

# ── Make project notebooks importable ─────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pyspark.sql import SparkSession

# ── Local paths (relative to project root) ────────────────────────────────────
ROOT        = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR    = os.path.join(ROOT, "local", "data")
LANDING     = os.path.join(DATA_DIR, "landing", "sales")
BRONZE_PATH = os.path.join(DATA_DIR, "bronze", "sales_raw")
SILVER_PATH = os.path.join(DATA_DIR, "silver", "sales_cleansed")
GOLD_PATH   = os.path.join(DATA_DIR, "gold",   "sales_summary_monthly")

# ── Spark session with Delta Lake ──────────────────────────────────────────────
builder = (
    SparkSession.builder
    .appName("azure-lakehouse-local")
    .config("spark.sql.extensions",              "io.delta.sql.DeltaSparkSessionExtension")
    .config("spark.sql.catalog.spark_catalog",   "org.apache.spark.sql.delta.catalog.DeltaCatalog")
    .config("spark.databricks.delta.preview.enabled",       "true")
    .config("spark.databricks.delta.optimizeWrite.enabled", "true")
    .config("spark.sql.shuffle.partitions", "4")  # small local cluster
    .master("local[*]")
)

spark = builder.getOrCreate()
spark.sparkContext.setLogLevel("WARN")

print(f"\n{'='*60}")
print(f"  Spark {spark.version}  |  Delta Lake local runner")
print(f"{'='*60}\n")

# ══════════════════════════════════════════════════════════════
# BRONZE — ingest raw CSV
# ══════════════════════════════════════════════════════════════
from pyspark.sql.functions import current_timestamp, lit, input_file_name

print("[bronze] Reading CSV from", LANDING)
raw_df = (
    spark.read
    .format("csv")
    .option("header", "true")
    .option("inferSchema", "true")
    .load(LANDING)
    .withColumn("_ingested_at", current_timestamp())
    .withColumn("_source_file", input_file_name())
    .withColumn("_source_path", lit(LANDING))
)

print(f"[bronze] Raw rows: {raw_df.count():,}")

raw_df.write.format("delta").mode("overwrite").save(BRONZE_PATH)
print(f"[bronze] Written -> {BRONZE_PATH}\n")

# ══════════════════════════════════════════════════════════════
# SILVER — cleanse + MERGE
# ══════════════════════════════════════════════════════════════
from pyspark.sql.functions import trim, col, to_date
from pyspark.sql.types import DoubleType, LongType
from delta.tables import DeltaTable

print("[silver] Reading bronze...")
bronze_df = spark.read.format("delta").load(BRONZE_PATH)

cleansed_df = (
    bronze_df
    .dropna(how="all")
    .dropDuplicates(["sale_id"])
    .withColumn("sale_id",    trim(col("sale_id")))
    .withColumn("product_id", trim(col("product_id")))
    .withColumn("region",     trim(col("region")))
    .withColumn("amount",     col("amount").cast(DoubleType()))
    .withColumn("quantity",   col("quantity").cast(LongType()))
    .withColumn("sale_date",  to_date(col("sale_date"), "yyyy-MM-dd"))
    .withColumn("_transformed_at", current_timestamp())
)

print(f"[silver] Cleansed rows: {cleansed_df.count():,}")

if DeltaTable.isDeltaTable(spark, SILVER_PATH):
    target = DeltaTable.forPath(spark, SILVER_PATH)
    (
        target.alias("t")
        .merge(cleansed_df.alias("s"), "t.sale_id = s.sale_id")
        .whenMatchedUpdateAll()
        .whenNotMatchedInsertAll()
        .execute()
    )
    print("[silver] MERGE complete")
else:
    cleansed_df.write.format("delta").mode("overwrite").save(SILVER_PATH)
    print("[silver] Initial write complete")

print(f"[silver] Written -> {SILVER_PATH}\n")

# ══════════════════════════════════════════════════════════════
# GOLD — monthly aggregates
# ══════════════════════════════════════════════════════════════
from pyspark.sql.functions import (
    sum as _sum, count, avg, max as _max,
    date_trunc, year, month,
)

print("[gold] Building monthly aggregates...")
silver_df = spark.read.format("delta").load(SILVER_PATH)

gold_df = (
    silver_df
    .withColumn("sale_month", date_trunc("month", col("sale_date")))
    .groupBy("sale_month", "product_id", "region")
    .agg(
        _sum("amount").alias("total_revenue"),
        _sum("quantity").alias("total_units"),
        count("sale_id").alias("transaction_count"),
        avg("amount").alias("avg_order_value"),
        _max("amount").alias("max_order_value"),
    )
    .withColumn("year",  year(col("sale_month")))
    .withColumn("month", month(col("sale_month")))
    .withColumn("_aggregated_at", current_timestamp())
)

gold_df.write.format("delta").mode("overwrite").partitionBy("year", "month").save(GOLD_PATH)
print(f"[gold] Written -> {GOLD_PATH}\n")

# ══════════════════════════════════════════════════════════════
# Results preview
# ══════════════════════════════════════════════════════════════
print("=" * 60)
print("  GOLD — top 10 months by revenue")
print("=" * 60)
(
    spark.read.format("delta").load(GOLD_PATH)
    .orderBy(col("total_revenue").desc())
    .select("year", "month", "product_id", "region", "total_revenue", "transaction_count")
    .show(10, truncate=False)
)

print("=" * 60)
print("  Delta table history (silver)")
print("=" * 60)
DeltaTable.forPath(spark, SILVER_PATH).history().select(
    "version", "timestamp", "operation", "operationParameters"
).show(5, truncate=False)

spark.stop()
print("\nDone.")
