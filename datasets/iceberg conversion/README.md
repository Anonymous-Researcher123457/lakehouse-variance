# CSV → Iceberg Conversion Tool

This repository provides a Spark-based utility for converting a directory of CSV files into Apache Iceberg tables, using an explicit JSON schema definition.

The tool is designed to be:

- engine-agnostic (Iceberg-native, no SQL DDL required),
- reproducible (explicit schemas, deterministic table locations),
- suitable for benchmarks and research workloads (e.g. IMDB, TPC-DS).

## Overview

The conversion process works as follows:

1. **Input**
- A directory of CSV files (one file per table)
- A JSON schema file mapping table → column → datatype

2. **Processing**
- Spark reads each CSV using the provided schema
- Column names are sanitised for Iceberg compatibility

3. **Output**
- Iceberg tables are created (or replaced) in a filesystem-backed Iceberg warehouse
- Table schemas are stored in Iceberg metadata (metadata/v*.metadata.json)

## Requirements

- Python 3.8+
- Apache Spark 3.x with Iceberg support
- Iceberg Spark runtime JARs available on the classpath

## Usage
````
python3 csv_to_iceberg.py \
  --db imdb \
  --csv-dir /path/to/imdb/csv \
  --schema /path/to/trino_datatypes.json \
  --warehouse /mnt/iceberg/warehouse \
  --header