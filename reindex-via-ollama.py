"""
Direct-Ollama reindex helper for Hindsight on Windows.

Works around hindsight-admin reindex-embeddings (PR #1258) which hardcodes
the embedder to local sentence-transformers — locking CPU-torch venvs into
a 100% CPU melt for the duration of the reindex (hours on 50K-row banks).

This script reads NULL-embedding rows from memory_units + mental_models in
batches, POSTs the source text to Ollama's OpenAI-compatible /v1/embeddings
endpoint, and UPDATEs each row with the returned vector. Bursty GPU pattern
(safe on RTX 5080 mobile / Blackwell + Optimus per ComfyUI behavior),
~12 rows/sec on a single 0.6B-param embedding model, resumable.

Configurable via env vars (defaults shown):
    HINDSIGHT_DB_URL                     postgresql://postgres@localhost:5432/hindsight
    OLLAMA_URL                           http://localhost:11434/v1/embeddings
    EMBEDDING_MODEL                      qwen3-embedding:0.6b
    REINDEX_BATCH_SIZE                   32     (rows per Ollama call)
    REINDEX_COMMIT_EVERY                 256    (commit every N rows)
    REINDEX_VENV_SITE_PACKAGES           G:/hindsight-local/hindsight-api-slim/.venv/Lib/site-packages
                                         (path to a venv containing psycopg2)

Usage (PowerShell):
    & "G:\\hindsight-local\\hindsight-api-slim\\.venv\\Scripts\\python.exe" reindex-via-ollama.py

The script needs `psycopg2` (NOT `psycopg`/psycopg3 — Hindsight's slim venv
ships psycopg2-binary 2.9.x, not psycopg3). It will use whatever
site-packages dir REINDEX_VENV_SITE_PACKAGES points at, defaulting to the
slim venv that ships with hindsight-api-slim.

License: MIT (same as the rest of this repo).
"""

import os
import sys
import time
import json
import urllib.request
import urllib.error

# Locate a venv with psycopg2 — defaults to the hindsight-api-slim venv
VENV_SITE = os.environ.get(
    "REINDEX_VENV_SITE_PACKAGES",
    r"G:\hindsight-local\hindsight-api-slim\.venv\Lib\site-packages",
)
if VENV_SITE and os.path.isdir(VENV_SITE):
    sys.path.insert(0, VENV_SITE)

try:
    import psycopg2
except ImportError:
    sys.exit(
        "ERROR: psycopg2 not found. Set REINDEX_VENV_SITE_PACKAGES to a venv "
        "containing psycopg2-binary, or install it into the active Python."
    )

DB_URL = os.environ.get("HINDSIGHT_DB_URL", "postgresql://postgres@localhost:5432/hindsight")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/v1/embeddings")
MODEL = os.environ.get("EMBEDDING_MODEL", "qwen3-embedding:0.6b")
BATCH_ROWS = int(os.environ.get("REINDEX_BATCH_SIZE", "32"))
COMMIT_EVERY = int(os.environ.get("REINDEX_COMMIT_EVERY", "256"))
PROGRESS_EVERY = 10  # log every N batches


def embed_batch(texts):
    """POST a batch of texts to Ollama's OpenAI-compatible endpoint."""
    body = json.dumps({"model": MODEL, "input": texts}).encode("utf-8")
    req = urllib.request.Request(
        OLLAMA_URL,
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.loads(resp.read())
    return [d["embedding"] for d in data["data"]]


def vec_to_pg(vec):
    """Format a list of floats as a pgvector literal."""
    return "[" + ",".join(f"{v:.7f}" for v in vec) + "]"


def reindex_table(cur, table, source_col):
    """Walk NULL-embedding rows, embed via Ollama, UPDATE in place."""
    print(f"\n=== {table}.embedding (source: {source_col}) ===", flush=True)

    cur.execute(f"SELECT COUNT(*) FROM {table} WHERE embedding IS NULL")
    total_null = cur.fetchone()[0]
    print(f"  rows to fill: {total_null}", flush=True)
    if total_null == 0:
        print("  nothing to do", flush=True)
        return 0

    filled = 0
    batches_done = 0
    rows_since_commit = 0
    start = time.time()

    while True:
        cur.execute(
            f"SELECT id, {source_col} FROM {table} "
            f"WHERE embedding IS NULL AND {source_col} IS NOT NULL "
            f"ORDER BY id LIMIT %s",
            (BATCH_ROWS,),
        )
        rows = cur.fetchall()
        if not rows:
            break

        ids = [r[0] for r in rows]
        texts = [r[1] for r in rows]

        try:
            vecs = embed_batch(texts)
        except Exception as e:
            print(f"  embed error after {filled} rows: {e!r}", flush=True)
            time.sleep(5)
            continue

        for id_, vec in zip(ids, vecs):
            cur.execute(
                f"UPDATE {table} SET embedding = %s::vector WHERE id = %s",
                (vec_to_pg(vec), id_),
            )

        filled += len(rows)
        rows_since_commit += len(rows)
        batches_done += 1

        if rows_since_commit >= COMMIT_EVERY:
            cur.connection.commit()
            rows_since_commit = 0

        if batches_done % PROGRESS_EVERY == 0:
            elapsed = time.time() - start
            rate = filled / elapsed if elapsed > 0 else 0
            remaining = (total_null - filled) / rate if rate > 0 else 0
            print(
                f"  {filled}/{total_null}  ({rate:.1f} rows/s, ETA {remaining/60:.1f} min)",
                flush=True,
            )

    cur.connection.commit()
    elapsed = time.time() - start
    rate = filled / elapsed if elapsed > 0 else 0
    print(
        f"  DONE: {filled} rows in {elapsed/60:.1f} min ({rate:.1f} rows/s)",
        flush=True,
    )
    return filled


def main():
    print(f"Connecting to {DB_URL}", flush=True)
    print(f"Embedder: {MODEL} via {OLLAMA_URL}", flush=True)
    print(f"Batch: {BATCH_ROWS} rows / Ollama call, commit every {COMMIT_EVERY}", flush=True)

    with psycopg2.connect(DB_URL) as conn:
        with conn.cursor() as cur:
            n1 = reindex_table(cur, "memory_units", "text")
            n2 = reindex_table(cur, "mental_models", "content")

    print(f"\n=== TOTAL: {n1 + n2} rows reindexed via Ollama ===", flush=True)


if __name__ == "__main__":
    main()
