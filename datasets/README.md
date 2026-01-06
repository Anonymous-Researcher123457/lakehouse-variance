# Datasets

This repository uses three well-established analytical benchmarks to evaluate query execution and system behaviour across structured workloads:

- TPC-DS
- JOB (Join Order Benchmark)
- SSB (Star Schema Benchmark)

Each dataset differs in how it is distributed and how it is ingested into the system.

| Dataset | Original Format |        Notes        |
|:-------:|:---------------:|:-------------------:|
| TPC-DS  |     Iceberg     |         N/A         |
|   JOB   |       CSV       | Requires conversion |
|   SSB   |       CSV       | Requires conversion |

### TPC-DS

In this project, we use an Iceberg-native variant is provided by:
- https://github.com/MOBIN-F/iceberg-spark-tpcds-benchmark

This implementation:

- Generates TPC-DS data directly in Iceberg format
- Avoids CSV ingestion overhead
- Provides tables that are immediately queryable by Spark and Trino

### JOB (Join Order Benchmark)

JOB is a classic benchmark designed to evaluate join ordering and optimizer behaviour using real IMDB-derived data.

Source:
- https://github.com/gregrahn/join-order-benchmark

Characteristics:
- Distributed as raw CSV files
-No native Iceberg or Parquet layout
-Schema defined externally

In this repository: 
- JOB CSV files must be converted to Iceberg tables before use
- The schema is provided in JOB_Trino_Schema.json
- Conversion is performed using the scripts in the Iceberg conversion directory

### SSB (Star Schema Benchmark)
SSB is a star-schema benchmark derived from TPC-H, commonly used for analytical query evaluation.

Source:

- https://github.com/electrum/ssb-dbgen

Characteristics:

- Generates raw CSV files
- Requires external schema definition
- No native Iceberg support

In this repository:

- SSB CSV files must be converted to Iceberg tables before use
- The schema is provided in SSB_Trino_Schema.json
- Conversion is handled via the Iceberg conversion directory