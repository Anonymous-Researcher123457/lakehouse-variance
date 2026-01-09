## Docker Images

This directory contains two custom Docker images used to support workload execution and trace collection.

---

### `trino/`

This image provides a custom Trino deployment based on the latest Trino Docker release.

including:
- A preconfigured Trino installation
- A built-in Prometheus Node Exporter for resource monitoring
- JMX exporter configuration for JVM-level metrics
- Custom entrypoint and configuration logic

This image is used as the execution backend for all experiments, ensuring a consistent Trino version and monitoring setup across clusters.

---

### `trino-client/`

This image provides the client-side tooling for interacting with Trino and executing workloads.

It includes:
- The SQL query templates used in the experiments
- Python and shell scripts to register catalogs, load tables, and execute workloads
- Helper utilities for credential checks and environment validation
- A lightweight runtime for orchestrating query execution

This image is responsible for issuing queries to Trino, collecting results, and producing the raw execution traces used in downstream analysis.

---
