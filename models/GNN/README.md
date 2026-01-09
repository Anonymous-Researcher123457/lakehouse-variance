## Graph Neural Network (GNN)

This directory contains the result artefacts produced by the Graph Neural Network (GNN)–based cost and runtime estimation experiments.

These experiments follow the work conducted in the *Zero-Shot Cost Estimation* line of work from the Data Management Lab:

https://github.com/DataManagementLab/zero-shot-cost-estimation/tree/main

---

## Content

### Results/
This directory is organised by workload and configuration:

- **Baseline_IMDB/**
- **Baseline_SSB/**
- **Baseline_TPCDS/**
- **Local_IMDB/**
- **Local_SSB/**
- **Local_TPCDS/**

Each subdirectory corresponds to a specific dataset and execution regime.
The CSV files in each results directory contain **both training and evaluation outputs**.

Specifically:
- The first portion of each CSV records metrics and configuration details from the **training phase**.
- The latter portion reports performance on a held-out **evaluation/test split**.

### table_3.ipynb

This notebook is used to **post-process and summarise the GNN evaluation results** reported in Table 3 of the paper.

It loads the prediction CSVs produced by the GNN pipeline and computes aggregate error metrics across datasets and execution regimes.

Specifically, it:
- Reads per-query ground-truth and prediction values from the result CSVs
- Filters invalid or zero-runtime entries
- Computes:
  - Mean Absolute Error (MAE)
  - Median QError (P50)
  - Tail QError (P99)

The outputs printed by this notebook correspond directly to the values reported in the paper’s GNN evaluation table.

