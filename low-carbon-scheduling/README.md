## Low-Carbon Scheduling

This directory contains the code and data used for the **low-carbon scheduling experiments (Study 4)**.

It implements the scheduling logic, workload simulation, and analysis pipelines used to evaluate how runtime uncertainty and carbon-intensity signals affect scheduling decisions and downstream emissions.

---

### Content

- **CL_data/**  
  Carbon-intensity time series and auxiliary datasets used by the schedulers.


- **src/**  
  Core implementation of the scheduling framework:
  - `carbon.py` – carbon-intensity handling and interpolation
  - `scheduler.py` – scheduling algorithms
  - `workload.py` – workload abstractions
  - `experiment.py` – experiment orchestration
  - `stats.py` – metric computation and aggregation
  - `plot.py` – visualisation utilities


- **config.py**  
  Centralised configuration for experiments.


- **Main.ipynb**  
  Primary notebook used to run experiments and generate results.


- **Main_Variance_Aware.ipynb**  
  Variant of the main notebook used for variance-aware scheduling experiments.

