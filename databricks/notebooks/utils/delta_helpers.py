# Shared Delta Lake utility helpers — imported by Bronze / Silver / Gold notebooks.

from delta.tables import DeltaTable
from pyspark.sql import DataFrame, SparkSession


def table_exists(spark: SparkSession, path: str) -> bool:
    """Return True if a Delta table exists at *path*."""
    return DeltaTable.isDeltaTable(spark, path)


def get_delta_table(spark: SparkSession, path: str) -> DeltaTable:
    return DeltaTable.forPath(spark, path)


def upsert(
    spark: SparkSession,
    source_df: DataFrame,
    target_path: str,
    merge_key: str,
) -> None:
    """MERGE *source_df* into the Delta table at *target_path* on *merge_key*."""
    if table_exists(spark, target_path):
        target = get_delta_table(spark, target_path)
        (
            target.alias("t")
            .merge(source_df.alias("s"), f"t.{merge_key} = s.{merge_key}")
            .whenMatchedUpdateAll()
            .whenNotMatchedInsertAll()
            .execute()
        )
    else:
        source_df.write.format("delta").mode("overwrite").save(target_path)


def optimize_and_vacuum(spark: SparkSession, table_name: str, zorder_cols: list[str] | None = None) -> None:
    """Run OPTIMIZE (with optional ZORDER) and VACUUM on a registered Delta table."""
    zorder_clause = f"ZORDER BY ({', '.join(zorder_cols)})" if zorder_cols else ""
    spark.sql(f"OPTIMIZE {table_name} {zorder_clause}")
    spark.sql(f"VACUUM {table_name} RETAIN 168 HOURS")


def get_latest_watermark(spark: SparkSession, table_name: str, watermark_col: str):
    """Return the MAX value of *watermark_col* from a registered Delta table."""
    row = spark.sql(f"SELECT MAX({watermark_col}) AS wm FROM {table_name}").first()
    return row["wm"] if row else None
