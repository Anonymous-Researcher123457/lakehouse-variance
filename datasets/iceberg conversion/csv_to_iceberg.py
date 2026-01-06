from __future__ import annotations

import argparse
import json
import logging
import os
import re
from pathlib import Path
from typing import Any, Dict, Optional

from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType, StructField,
    StringType, IntegerType, LongType, DoubleType, BooleanType,
    DateType, TimestampType, DecimalType
)
from pyspark.sql.utils import AnalysisException

logger = logging.getLogger("py4j")
logger.setLevel(logging.ERROR)


def sanitize_column_name(col_name: str) -> str:
    col_name = col_name.replace("\t", "_").replace(" ", "_")
    col_name = re.sub(r"[^\w]", "_", col_name)
    col_name = re.sub(r"__+", "_", col_name)
    if re.match(r"^\d", col_name):
        col_name = f"col_{col_name}"
    return col_name.lower()


def parse_trino_type(trino_type: str):
    """
    Convert a Trino-like type string (e.g., INTEGER, BIGINT, VARCHAR, DECIMAL(12,2))
    into a Spark SQL type.
    """
    t = trino_type.strip().upper()

    # Parse DECIMAL(P,S)
    m = re.match(r"DECIMAL\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)", t)
    if m:
        precision = int(m.group(1))
        scale = int(m.group(2))
        precision = min(precision, 38)
        scale = min(scale, precision)
        return DecimalType(precision=precision, scale=scale)

    base = t.split("(")[0].strip()

    trino_to_spark = {
        "INTEGER": IntegerType(),
        "INT": IntegerType(),
        "SMALLINT": IntegerType(),
        "BIGINT": LongType(),
        "VARCHAR": StringType(),
        "CHAR": StringType(),
        "BOOLEAN": BooleanType(),
        "DOUBLE": DoubleType(),
        "REAL": DoubleType(),
        "FLOAT": DoubleType(),
        "DATE": DateType(),
        "TIMESTAMP": TimestampType(),
        "TIMESTAMP WITH TIME ZONE": TimestampType(),
    }

    return trino_to_spark.get(base, StringType())


def build_spark_schema(column_type_dict: Dict[str, str]) -> StructType:
    fields = []
    for col, trino_type in column_type_dict.items():
        spark_type = parse_trino_type(trino_type)
        fields.append(StructField(sanitize_column_name(col), spark_type, True))
    return StructType(fields)


def make_spark(iceberg_catalog: str, warehouse: str, app_name: str = "CSV to Iceberg") -> SparkSession:
    warehouse_abs = os.path.abspath(warehouse)

    spark = (
        SparkSession.builder
        .appName(app_name)
        .config(f"spark.sql.catalog.{iceberg_catalog}", "org.apache.iceberg.spark.SparkCatalog")
        .config(f"spark.sql.catalog.{iceberg_catalog}.type", "hadoop")
        .config(f"spark.sql.catalog.{iceberg_catalog}.warehouse", warehouse_abs)
        .config(f"spark.sql.catalog.{iceberg_catalog}.write.metadata.statistics.enabled", "true")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("ERROR")
    return spark


def load_trino_schema(schema_path: Path) -> Dict[str, Dict[str, str]]:
    """
    Expected format:
    {
      "table_a": {"col1": "INTEGER", "col2": "VARCHAR", ...},
      "table_b": {"x": "DECIMAL(12,2)", ...}
    }
    """
    with schema_path.open("r", encoding="utf-8") as f:
        obj = json.load(f)

    if not isinstance(obj, dict):
        raise ValueError("Schema JSON must be an object mapping table_name -> {column -> type}.")

    for tbl, cols in obj.items():
        if not isinstance(cols, dict):
            raise ValueError(f"Schema for table '{tbl}' must be an object of column->type.")
    return obj


def convert_csv_dir_to_iceberg(
    spark: SparkSession,
    db_name: str,
    csv_dir: Path,
    schema_json: Dict[str, Dict[str, str]],
    iceberg_catalog: str,
    warehouse: Path,
    delimiter: str,
    header: bool,
    quote: str,
    escape: str,
    target_file_size_bytes: int,
    mode: str,
) -> None:
    """
    mode:
      - "create_or_replace": createOrReplace
      - "append": append
      - "create": create (fail if exists)
    """
    csv_dir = csv_dir.resolve()
    warehouse = warehouse.resolve()

    if not csv_dir.exists():
        raise FileNotFoundError(f"CSV directory not found: {csv_dir}")

    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {iceberg_catalog}.{db_name}")

    print(f"CSV dir: {csv_dir}")
    print(f"Iceberg warehouse: {warehouse}")
    print(f"Writing to: {iceberg_catalog}.{db_name}.*")
    print(f"delimiter={repr(delimiter)} header={header}")

    for csv_file in sorted(csv_dir.iterdir()):
        if not csv_file.is_file() or csv_file.suffix.lower() != ".csv":
            continue

        table_name = csv_file.stem
        if table_name not in schema_json:
            print(f"No schema found for table '{table_name}' in {db_name}, skipping.")
            continue

        table_schema = build_spark_schema(schema_json[table_name])

        try:
            reader = (
                spark.read
                .option("header", str(header).lower())
                .option("delimiter", delimiter)
                .option("quote", quote)
                .option("escape", escape)
                .schema(table_schema)
            )
            df = reader.csv(str(csv_file))
        except AnalysisException as e:
            print(f"Failed to read {csv_file}: {e}")
            continue

        df = df.toDF(*[sanitize_column_name(c) for c in df.columns])

        schema_dir = warehouse / f"{db_name}.db"
        schema_dir.mkdir(parents=True, exist_ok=True)
        table_path = schema_dir / table_name

        ident = f"{iceberg_catalog}.{db_name}.{table_name}"
        print(f"  → Writing table: {ident}  (source: {csv_file.name})")

        writer = (
            df.writeTo(ident)
            .option("location", str(table_path))
            .tableProperty("write.target-file-size-bytes", str(target_file_size_bytes))
            .using("iceberg")
        )

        if mode == "create_or_replace":
            writer.createOrReplace()
        elif mode == "create":
            writer.create()
        elif mode == "append":
            writer.append()
        else:
            raise ValueError(f"Unknown mode: {mode}")

    print(f"Finished: {iceberg_catalog}.{db_name}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Convert a directory of CSV files into Iceberg tables using Spark.")
    ap.add_argument("--db", required=True, help="Iceberg namespace/database name (e.g., imdb, tpcds).")
    ap.add_argument("--csv-dir", required=True, help="Directory containing per-table CSV files (one .csv per table).")
    ap.add_argument("--schema", required=True, help="Path to Trino schema datatypes  {table -> column -> type}.")
    ap.add_argument("--warehouse", required=True, help="Output Iceberg warehouse directory.")
    ap.add_argument("--catalog", default="iceberg", help="Spark catalog name (default: iceberg).")

    ap.add_argument("--delimiter", default="|", help="CSV delimiter (default: '|'). Use '\\t' for tab.")
    ap.add_argument("--header", action="store_true", help="CSV files have a header row (default: false).")

    ap.add_argument("--quote", default="\u0000", help="CSV quote character (default disables quoting).")
    ap.add_argument("--escape", default="\\", help="CSV escape character (default: backslash).")

    ap.add_argument("--target-file-size-bytes", type=int, default=536870912, help="Target Iceberg file size (default: 512MB).")
    ap.add_argument(
        "--mode",
        choices=["create_or_replace", "create", "append"],
        default="create_or_replace",
        help="Write mode (default: create_or_replace).",
    )

    args = ap.parse_args()

    delimiter = args.delimiter.encode("utf-8").decode("unicode_escape")  # lets users pass "\t"

    spark = make_spark(args.catalog, args.warehouse)
    try:
        schema_json = load_trino_schema(Path(args.schema))
        convert_csv_dir_to_iceberg(
            spark=spark,
            db_name=args.db,
            csv_dir=Path(args.csv_dir),
            schema_json=schema_json,
            iceberg_catalog=args.catalog,
            warehouse=Path(args.warehouse),
            delimiter=delimiter,
            header=args.header,
            quote=args.quote,
            escape=args.escape,
            target_file_size_bytes=args.target_file_size_bytes,
            mode=args.mode,
        )
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
