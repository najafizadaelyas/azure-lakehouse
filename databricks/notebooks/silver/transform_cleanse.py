# Databricks notebook: Silver — Transform & Cleanse
# Reads from Bronze Delta, applies cleansing / deduplication / schema enforcement,
# and upserts (MERGE) into the Silver Delta table.

from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, trim, upper, to_date, to_timestamp,
    when, coalesce, lit, current_timestamp,
    regexp_replace,
)
from pyspark.sql.types import DoubleType, LongType
from delta.tables import DeltaTable

# ── Parameters ─────────────────────────────────────────────────────────────────
dbutils.widgets.text("bronze_table",  "sales_raw",       "Bronze table")
dbutils.widgets.text("silver_table",  "sales_cleansed",  "Silver table")
dbutils.widgets.text("merge_key",     "sale_id",         "Merge key column")
dbutils.widgets.text("adls_account",  "",                "ADLS account name")

BRONZE_TABLE = dbutils.widgets.get("bronze_table")
SILVER_TABLE = dbutils.widgets.get("silver_table")
MERGE_KEY    = dbutils.widgets.get("merge_key")
ADLS_ACCOUNT = dbutils.widgets.get("adls_account")

BRONZE_PATH  = f"abfss://bronze@{ADLS_ACCOUNT}.dfs.core.windows.net/{BRONZE_TABLE}"
SILVER_PATH  = f"abfss://silver@{ADLS_ACCOUNT}.dfs.core.windows.net/{SILVER_TABLE}"

spark: SparkSession = spark

# ── Read Bronze ─────────────────────────────────────────────────────────────────
bronze_df = spark.read.format("delta").load(BRONZE_PATH)

# ── Cleanse ─────────────────────────────────────────────────────────────────────
cleansed_df = (
    bronze_df
    # Drop fully-null rows
    .dropna(how="all")
    # Drop duplicates on the natural key
    .dropDuplicates([MERGE_KEY])
    # Normalise string columns
    .transform(lambda df: df.select([
        trim(col(c)).alias(c) if t == "string" else col(c)
        for c, t in df.dtypes
    ]))
    # Cast common numeric columns if present
    .transform(lambda df: (
        df.withColumn("amount",   col("amount").cast(DoubleType()))
          .withColumn("quantity", col("quantity").cast(LongType()))
        if "amount" in df.columns else df
    ))
    # Standardise date columns
    .transform(lambda df: (
        df.withColumn("sale_date", to_date(col("sale_date"), "yyyy-MM-dd"))
        if "sale_date" in df.columns else df
    ))
    .withColumn("_transformed_at", current_timestamp())
)

print(f"[silver] Cleansed row count: {cleansed_df.count():,}")

# ── MERGE into Silver Delta ────────────────────────────────────────────────────
if DeltaTable.isDeltaTable(spark, SILVER_PATH):
    silver_table = DeltaTable.forPath(spark, SILVER_PATH)

    (
        silver_table.alias("target")
        .merge(
            cleansed_df.alias("source"),
            f"target.{MERGE_KEY} = source.{MERGE_KEY}",
        )
        .whenMatchedUpdateAll()
        .whenNotMatchedInsertAll()
        .execute()
    )
    print("[silver] MERGE complete")
else:
    cleansed_df.write.format("delta").mode("overwrite").save(SILVER_PATH)
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS silver.{SILVER_TABLE}
        USING DELTA
        LOCATION '{SILVER_PATH}'
    """)
    print("[silver] Initial write complete")

# ── Optimize + Z-ORDER ─────────────────────────────────────────────────────────
spark.sql(f"OPTIMIZE silver.{SILVER_TABLE} ZORDER BY ({MERGE_KEY})")
print("[silver] OPTIMIZE + ZORDER complete")
