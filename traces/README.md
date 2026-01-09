# Traces  

This directory contains all execution traces, derived workload logs, and auxiliary tooling used in the experimental evaluation.

The structure is organised by **study** and **cluster**, with tooling provided to aid with interacting and distributing data.

---

## Overview

This directory contains execution traces and derived workload summaries organised as:

**study** / **cluster** / **type** / **run** 

For each level:

- **Study** (study_X)\
Represents the experiment the traces are used in.


- **Cluster** (e.g., AWS, GCP, Azure, Self_Hosted) \
Independent execution environments. Each cluster is treated as a standalone root by the tooling.


- **Type** (e.g., Fixed_Nodes, Warm_Cache, Local_Data, etc.) \
Defines the experimental condition of the lakehouse.


- **Run** \
A single execution of a workload under a given condition.
Each run contains:

  - A zipped archive of the run directory

  - A derived workload summary file:
  `Workload_log_<Type>_<RUN>.ndjson`
  containing:
    - `query_id`
    - `Runtime (s)`
    - `elapsed_s`
    - `execution_s`
    - `planning_s`
    - `resource_waiting_s`

 **Note:** As experiments were executed across heterogeneous clusters with varying
 resource availability, not all configurations contain the full set of 99 queries for
 every run. The notebooks therefore compute statistics over the subset of queries that
 completed successfully for each configuration.
---

## Tooling 

### main.sh 

Master orchestration script.  

Supported operations:

- `--scrub`   (removes private paths and IP addresses)
- `--summary` (workload log generation)
- `--zip`  (compress raw trace files into a zip)   
- `--unzip` (extract raw trace files from zip)

Order of flags = order of execution.

Examples:
- Initial access to raw traces: `./main.sh --unzip`
- Prepare traces for sharing: `./main.sh --scrub --summary --zip`

Data availability:
The complete raw trace archives exceed GitHub’s file size limits and are therefore not included directly in this repository. To preserve author anonymity during peer review, these traces are not yet hosted externally. A permanent, anonymous download link will be provided soon.

---

## Reproducing Results
### table_1.ipynb (Study 1)

This notebook reproduces the summary statistics reported in **Study 1** of the paper.
It loads the derived workload logs for a given cluster and lakehouse type, aggregates per-query runtimes across repeated runs, and reports:
- Mean query runtime across runs (Avg, Std, P50, P99)
- Per-query repeatability statistics (Std and CV, with Avg, P50, P99)

The output includes both a human-readable table and LaTeX-formatted rows for direct inclusion.
### table_2.ipynb (Study 2)

This notebook reproduces the comparative (delta) results reported in **Study 2** of the paper.
It loads workload logs for a baseline configuration and a variant configuration, computes the same summary statistics as in Table 1 for each, and then reports:
- Absolute differences in mean runtime
- Changes in coefficient of variation (CV) statistics
- Per-metric deltas used in the paper’s comparison tables

The output includes both a human-readable table and LaTeX-formatted rows for direct inclusion.