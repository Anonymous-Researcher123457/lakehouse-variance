import argparse
import json
import time
from pathlib import Path
from datetime import datetime, timezone

import requests
import trino
import fsspec

# Default attributes if none are supplied.
from config import *

def join_url(prefix: str, *parts: str) -> str:
    prefix = prefix.rstrip("/")
    tail = "/".join(p.strip("/\\") for p in parts if p)
    return f"{prefix}/{tail}" if tail else prefix

def upload_file(local_path: str, remote_url: str) -> None:
    # Use fsspec to upload temp file to object storage.
    # Works for s3://, abfs(s)://, gs://, file://, etc.
    with open(local_path, "rb") as fin, fsspec.open(remote_url, "wb") as fout:
        for chunk in iter(lambda: fin.read(1024 * 1024), b""):
            fout.write(chunk)

def load_queries_from_directory(directory_path):
    queries = []
    for file_path in sorted(Path(directory_path).glob("q*.sql")):
        queries.append((file_path.stem, file_path.read_text().strip()))
    return queries

def execute_query(query, query_id, trino_conn, trino_host, run_name, attempt, results_prefix, info_headers):
    cursor = trino_conn.cursor()
    start_perf = time.perf_counter()
    start_time = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        cursor.execute(query)
        for _ in cursor:
            pass
        end_perf = time.perf_counter()
        end_time = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        trino_query_id = cursor.stats["queryId"]
        duration = end_perf - start_perf

        print(f"[{query_id}] Runtime: {duration:.4f}s | Query ID: {trino_query_id}")

        # Scrape query info JSON from Trino UI API
        url = f"http://{trino_host}:{TRINO_PORT}/ui/api/query/{trino_query_id}"
        r = requests.get(url, headers=info_headers, timeout=30)
        if r.ok:
            doc = r.json()
            doc["metrics"] = {} 
            local_file = f"/tmp/{query_id}.json"
            with open(local_file, "w") as f:
                json.dump(doc, f, indent=2)

            remote = join_url(results_prefix, run_name, f"lakehouse_run_{attempt}", f"{query_id}.json")
            upload_file(local_file, remote)

        return start_time, end_time, duration
    except Exception as e:
        print(f"[{query_id}] Failed: {e}")
        return -1, -1, -1

def run_workload(queries, trino_conn, trino_host, run_name, attempts, results_prefix, info_headers):
    results = []
    for name, query in queries:
        s, e, d = execute_query(query, name, trino_conn, trino_host, run_name, attempts, results_prefix, info_headers)
        results.append({"query_id": name, "start_time": s, "end_time": e, "Runtime (s)": d})
    return results

def write_results(results_list, run_name, attempt, results_prefix):
    # Required temp store to keep json before uploading to object storage.
    local_log = f"/tmp/Workload_log_run_{attempt}.ndjson"
    with open(local_log, "w") as f:
        for entry in results_list:
            f.write(json.dumps(entry) + "\n")
    remote = join_url(results_prefix, run_name, f"Workload_log_run_{attempt}.ndjson")
    upload_file(local_log, remote)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run workload and upload results to cloud storage via fsspec.")
    parser.add_argument("--host", required=True)
    parser.add_argument("--attempt", type=int, default=1)
    parser.add_argument("--run_name", default="run1")
    parser.add_argument("--results_path", required=True,
                        help="Prefix like s3://bucket/Results | abfss://container@acct.dfs.core.windows.net/Results | gs://bucket/Results")
    parser.add_argument("--query_dir", default=QUERY_DIRECTORY)
    parser.add_argument("--trino_port", type=int, default=TRINO_PORT)
    parser.add_argument("--trino_user", default=TRINO_USER)
    parser.add_argument("--trino_catalog", default=TRINO_CATALOG)
    parser.add_argument("--trino_schema", default=TRINO_SCHEMA)
    args = parser.parse_args()

    TRINO_PORT = args.trino_port
    INFO_HEADERS = {"X-Trino-User": args.trino_user}

    # Establish a Trino connection
    trino_conn = trino.dbapi.connect(
        host=args.host, port=TRINO_PORT, user=args.trino_user,
        catalog=args.trino_catalog, schema=args.trino_schema
    )

    queries = load_queries_from_directory(args.query_dir)
    results = run_workload(queries, trino_conn, args.host, args.run_name, args.attempt, args.results_path, INFO_HEADERS)
    write_results(results, args.run_name, args.attempt, args.results_path)
