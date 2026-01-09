import torch
from pathlib import Path
import os
from sentence_transformers import SentenceTransformer
from abc import ABC
from transformers import AutoTokenizer


class SQLRepresentationEncoder(ABC):
    """
    Abstract base class for different SQL representation encoders.
    """

    def __init__(self):
        self.type = None
        self.approach = None

class TextSQLEncoder(SQLRepresentationEncoder):
    approach = "text"

    def __init__(self):
        super().__init__()
        self.type = "text"
        self.approach = "text"
        self.tokenizer = AutoTokenizer.from_pretrained(
            Path("\Model\tokenizer").resolve(),
            trust_remote_code=True
        )
        self.embed_tokens = torch.load(Path("embed_tokens.pt").resolve())
        self.shape = [5120]
        self.shape_label = ["XiYanSQL-QwenCoder-32B"]

    def parse_sql(self, sql_representation) -> torch.Tensor:
        encoded = self.tokenizer(sql_representation, return_tensors="pt", padding=True)
        input_ids = encoded["input_ids"].squeeze(0)

        token_embeddings = self.embed_tokens[input_ids].float()

        mean_embedding = token_embeddings.mean(dim=0)

        return mean_embedding.unsqueeze(0)
