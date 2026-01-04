import argparse
import trino

from typing import List

# Default attributes if none are supplied.
from config import *

def create_schema_if_missing(cursor, schema: str):
    cursor.execute(f"CREATE SCHEMA IF NOT EXISTS {TRINO_CATALOG}.{schema}")

def register_table(trino_cursor, schema: str, table_name: str, table_path: str):
    query = f"""
        CALL {TRINO_CATALOG}.system.register_table(
            schema_name => '{schema}',
            table_name => '{table_name}',
            table_location => '{table_path}',
            metadata_file_name => 'v1.metadata.json'
        )
    """
    try:
        print(f"Registering table: {table_name}")
        trino_cursor.execute(query)
        print(f"Successfully registered: {table_name}")
    except Exception as e:
        print(f"[ERROR] Failed to register {table_name}: {str(e)}")

def connect_trino(trino_host: str, schema: str):
    return trino.dbapi.connect(
        host=trino_host,
        port=TRINO_PORT,
        user=TRINO_USER,
        catalog=TRINO_CATALOG,
        schema=schema,
        http_scheme="http",
        session_properties={"query_max_run_time": TIME_OUT},
    )

def main(warehouse_path: str | None, schema: str, host: str, tables: List[str]):
    base_path = warehouse_path.rstrip("/")
    conn = connect_trino(host, schema)
    cursor = conn.cursor()

    create_schema_if_missing(cursor, schema)

    print(f"Found {len(tables)} tables to register in Trino...")
    for table in tables:
        table_path = f"{base_path}/{table}"
        register_table(cursor, schema, table, table_path)

    cursor.close()
    conn.close()
    print("Tables Imported!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--schema', required=True, help="Target schema to create/use")
    parser.add_argument('--host', required=True, help="Trino host (DNS or IP)")
    parser.add_argument("--tables", nargs="+", required=True, help="list of strings representing tables of schema")
    parser.add_argument('--warehouse', default=None, help="Base directory path to schema tables (e.g., s3://BUCKET/warehouse/SCHEMA/[TABLES])")
    args = parser.parse_args()
    main(args.warehouse, args.schema, args.host, args.tables)
