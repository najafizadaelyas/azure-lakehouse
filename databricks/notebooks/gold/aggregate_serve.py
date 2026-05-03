# Databricks notebook: Gold — Aggregate & Serve
# Reads from Silver, builds business-level aggregates, and writes Gold Delta tables
# optimised for BI / SQL Analytics consumption.

from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, sum as _sum, count, avg, max as _max,
    date_trunc, year, month, current_timestamp,
)
from delta.tables import DeltaTable

# ── Parameters ─────────────────────────────────────────────────────────────────
dbutils.widgets.text("silver_table", "sales_cleansed",        "Silver table")
dbutils.widgets.text("gold_table",   "sales_summary_monthly", "Gold table")
dbutils.widgets.text("adls_account", "",                       "ADLS account name")

SILVER_TABLE = dbutils.widgets.get("silver_table")
GOLD_TABLE   = dbutils.widgets.get("gold_table")
ADLS_ACCOUNT = dbutils.widgets.get("adls_account")

SILVER_PATH  = f"abfss://silver@{ADLS_ACCOUNT}.dfs.core.windows.net/{SILVER_TABLE}"
GOLD_PATH    = f"abfss://gold@{ADLS_ACCOUNT}.dfs.core.windows.net/{GOLD_TABLE}"

spark: SparkSession = spark

# ── Read Silver ────────────────────────────────────────────────────────────────
silver_df = spark.read.format("delta").load(SILVER_PATH)

# ── Aggregate: monthly sales summary ──────────────────────────────────────────
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

print(f"[gold] Aggregate row count: {gold_df.count():,}")

# ── Write Gold (full overwrite — aggregates are recomputed each run) ───────────
(
    gold_df.write
    .format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .partitionBy("year", "month")
    .save(GOLD_PATH)
)

spark.sql(f"""
    CREATE TABLE IF NOT EXISTS gold.{GOLD_TABLE}
    USING DELTA
    LOCATION '{GOLD_PATH}'
""")

# ── Vacuum stale files (retain 7 days) ────────────────────────────────────────
spark.sql(f"VACUUM gold.{GOLD_TABLE} RETAIN 168 HOURS")

# ── Optimize for BI scan patterns ─────────────────────────────────────────────
spark.sql(f"OPTIMIZE gold.{GOLD_TABLE} ZORDER BY (product_id, region)")

print(f"[gold] Written to {GOLD_PATH}")

# ── Quick validation ───────────────────────────────────────────────────────────
display(spark.sql(f"""
    SELECT year, month, COUNT(*) AS rows, SUM(total_revenue) AS revenue
    FROM gold.{GOLD_TABLE}
    GROUP BY year, month
    ORDER BY year DESC, month DESC
    LIMIT 12
"""))
