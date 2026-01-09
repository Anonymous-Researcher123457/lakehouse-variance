# Random Forest (RF)

The `RF/` subdirectory contains the full implementation of the Random Forest pipeline, including feature encoding, training, and evaluation.

---

### Content

- **Model/**  
  Core implementation of the Random Forest pipeline.

  - `Dataloader.py` – Loads and preprocesses NDJSON workload logs  
  - `sql_encoder.py` – Encodes SQL queries into vector representations  
  - `embed_tokens.pt` – Precomputed embedding weights  
  - `tokenizer/` – Tokeniser configuration and vocabulary  
  - `README.md` – Model-specific documentation  

- **Results/**  
  Stores trained models, predictions, and evaluation outputs. Subdirectories Include:
  - `Baseline_imdb/`
  - `Baseline_ssb/`
  - `Baseline_tpcds/`
  - `Local_imdb/`
  - `Local_ssb/`
  - `Local_tpcds/`

  Each contains:
  - `*_train.ndjson` – Training splits  
  - `*_test.ndjson` – Test splits  
  - `results_text.txt` – Summary metrics  
  - `values.csv` – Per-query predictions and ground truth  

- **train.ipynb**  
  Notebook used to train the Random Forest models and generate the reported results.

---

### Embedding Weights

The SQL token embeddings used by the RF model are derived from the **XiYanSQL-QwenCoder** project:

GitHub: https://github.com/XGenerationLab/XiYanSQL-QwenCoder

These embeddings are used to initialise the token-level representations prior to aggregation and Random Forest training. 