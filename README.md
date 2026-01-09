## Repository Overview

This repository contains the experimental artefacts for the paper:

**How Well Can Lakehouse Performance Be Predicted?  
An Empirical Exploration of Query Runtime Variance**

It includes all scripts, traces, models, and analysis notebooks required to reproduce the results reported in the paper.

The artefacts are organised by function (deployment, trace processing, modelling, and scheduling), with each top-level directory containing its own detailed `README.md`.

---

## Structure

- **clusters/**  
  Platform-specific deployment and orchestration scripts for running experiments on AWS, Azure, GCP, and local environments.

- **datasets/**  
  Dataset preprocessing utilities, including scripts for converting raw data into Iceberg-compatible formats.

- **docker/**  
  Custom Docker images for Trino and the Trino client used to execute workloads and collect traces.

- **low-carbon-scheduling/**  
  Code and notebooks used for the low-carbon scheduling experiments (Study 4), including schedulers, simulations, and analysis.

- **models/**  
  Machine learning models and result artefacts, including both RF and GNN-based predictors used in Study 3.

- **traces/**  
  Raw execution traces, derived workload summaries, and preprocessing tools used in Studies 1–2.

---

## Purpose

This repository is intended to support:

- Reproducibility of all experimental results
- Inspection of raw and processed traces
- Re-execution of workloads on new infrastructures
- Extension of the modelling and scheduling pipelines

Each subdirectory contains a dedicated `README.md` with detailed documentation of its contents and usage.

---

## Citation

If you use these artefacts, please cite the associated paper.

(Full citation to be added.)
