import numpy as np
import torch
import pandas as pd
import os
import sys

from torch.utils.data import Dataset, DataLoader
from sklearn.decomposition import PCA
grandparent_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if grandparent_dir not in sys.path:
    sys.path.insert(0, grandparent_dir)

from config import * 

class QueryDatasetRF(Dataset):
    def __init__(
        self,
        df: pd.DataFrame,
        sql_encoder=None,
        schema_encoder=None,
        system_encoder=None,
        pca_model=None,
    ):
        self.df = df.reset_index(drop=True)
        if not sql_encoder:
            raise ValueError(f"Error: An SQL Encoder must be provided")
        self.sql_encoder = sql_encoder
        self.schema_encoder = schema_encoder
        self.system_encoder = system_encoder
        self.samples = []
        self.pca_model = pca_model
        self._build_samples()


    def _build_samples(self):
        # 1. Precollect SQL embeddings
        sql_embeddings_list = []
        for row_idx, row in self.df.iterrows():
            if self.sql_encoder.approach == "graph":
                sql_representation = row["graph"]
            elif self.sql_encoder.approach == "onehot":
                sql_representation = row["explain_results"]
            else:
                sql_representation = row["SQL"]
            sql_embedding = self.sql_encoder.parse_sql(sql_representation).detach().cpu().numpy().squeeze(0)
            sql_embeddings_list.append(sql_embedding)
    
        # 2. Optionally fit PCA
        first_embedding_dim = sql_embeddings_list[0].shape[-1]
        apply_pca = first_embedding_dim > 5000
        use_pca = True
        self.pca_fitted_here = False

        if apply_pca and self.pca_model is None and use_pca:
            X_sql_embeddings = np.stack(sql_embeddings_list)  # (n_queries, input_dim)
            self.pca_model = PCA(n_components=4, random_state=SEED)
            self.pca_model.fit(X_sql_embeddings)
            self.pca_fitted_here = True  # when you fit PCA

        # 3. Build final samples
        self.samples = []
        for row_idx, row in self.df.iterrows():
            # Extract label
            label_value = float(row["label"])
            # Get precollected sql_embedding
            sql_embedding = sql_embeddings_list[row_idx]
    
            # Apply PCA if needed
            if apply_pca:
                sql_embedding = self.pca_model.transform(sql_embedding.reshape(1, -1))
    
            # Encode schema
            schema_data = None
            if self.schema_encoder:
                schema_data = self.schema_encoder.parse_schema(row["SQL"]).detach().cpu().numpy()
    
            # Encode system
            system_data = None
            if self.system_encoder:
                resources = {"workers": row["Number of Workers"], "cpu": 4.0, "mem": 64.0}
                system_data = self.system_encoder.parse_system(resources).detach().cpu().numpy()
    
            # Combine features
            if sql_embedding.ndim == 1:
                sql_embedding = sql_embedding.reshape(1, -1)
            feature_vector = [sql_embedding]
            if schema_data is not None:
                feature_vector.append(schema_data)
            if system_data is not None:
                feature_vector.append(system_data)
    
            feature_vector = np.concatenate(feature_vector, axis=1)
    
            if row_idx == 0:
                self.feature_names = []
                sql_dim = sql_embedding.shape[-1]
                schema_dim = schema_data.shape[-1] if schema_data is not None else 0
                system_dim = system_data.shape[-1] if system_data is not None else 0
    
                self.feature_names += [f"SQL_{i}" for i in range(sql_dim)]
                self.feature_names += [f"Schema_{i}" for i in range(schema_dim)]
                self.feature_names += [f"System_{i}" for i in range(system_dim)]
    
            self.samples.append((feature_vector, label_value, row["query_id"]))


       

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        return self.samples[idx]

def prepare_data_for_rf(df, sql_encoder, schema_encoder=None, system_encoder=None, pca_model=None):
    dataset = QueryDatasetRF(df, sql_encoder, schema_encoder, system_encoder, pca_model)
    X, y, query_ids = zip(*dataset)
    X = np.array(X)
    if X.ndim == 3 and X.shape[1] == 1:
        X = X.squeeze(1)
    y = np.array(y)

    # Return the newly fitted model if dataset fitted one
    if dataset.pca_fitted_here:
        return X, y, dataset.feature_names, dataset.pca_model, query_ids
    else:
        return X, y, dataset.feature_names, pca_model, query_ids