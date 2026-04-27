# Upgrading Hindsight to 1024-dim qwen3-embedding + vchord on native Windows

This is the validated end-to-end workflow for migrating an existing populated Hindsight install from `bge-small-en-v1.5` (384-dim, CPU torch, pgvector/HNSW) to `qwen3-embedding:0.6b` (1024-dim, Ollama GPU, vchord/vchordrq) — without leaving Windows, without Docker, without WSL2.

The README's `Using vchord with Hindsight on Windows` section gives the high-level shape. **This file is the actual playbook with the gotchas.** Everything below was lived end-to-end on the configuration in the next section.

---

## Validated configuration

Stack this was tested against (laptop):

- **OS:** Windows 11 24H2
- **GPU:** RTX 5080 mobile (Blackwell), Optimus
- **Postgres:** 17.9 native EnterpriseDB installer (NOT pg0, NOT Docker, NOT WSL2)
- **vchord:** built from this repo's `WINDOWS_BUILD.md` — `vchord.dll` 9.4 MB MSVC PE32+ x64
- **Hindsight:** `hindsight-api-slim` 0.5.4 (editable install of [PR #1258 branch](https://github.com/vectorize-io/hindsight/pull/1258) `feat/reindex-embeddings-clean`)
- **torch in slim venv:** 2.11.0+cpu (CPU only — relevant for the gotcha below)
- **Ollama:** native Windows installer (no WSL2), models at `G:\ollama\models`
- **Embedder:** `hf.co/CompendiumLabs/bge-small-en-v1.5-gguf` (380-dim, no re-embed needed) OR `qwen3-embedding:0.6b` (1024-dim, requires re-embed) — both via Ollama
- **Bank scale:** 51,947 memory_units + 29 mental_models across 8 banks

Live result on this hardware: CPU dropped from **100% sustained at 100°C** (CPU-torch embedder + cross-encoder reranker) to **~5% steady-state** with bursty GPU on Ollama.

---

## Gotchas you will hit

Read these BEFORE starting. They cost real time to discover.

### 1. `hindsight-admin reindex-embeddings` is hardcoded to local sentence-transformers

**This is the big one.** The `reindex-embeddings` command from [PR #1258](https://github.com/vectorize-io/hindsight/pull/1258) ignores `HINDSIGHT_API_EMBEDDINGS_PROVIDER` and unconditionally loads the model via sentence-transformers locally. On a CPU-torch venv this means the migration tool itself will run at 100% CPU for 2+ hours — defeating the entire point of moving the embedder to Ollama.

The help text says it respects `HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL` only. The `openai`/`tei`/`cohere` providers are not honored by this command.

**Workaround:** use the `reindex-via-ollama.py` helper in this repo. It uses `psycopg2` + `urllib.request` to POST text directly to Ollama's OpenAI-compatible `/v1/embeddings` endpoint and `UPDATE` the rows. Bursty GPU pattern, ~12 rows/sec on RTX 5080 mobile, resumable, CPU stays under 10%.

### 2. Hindsight does not auto-load `.env`

The `hindsight-api.exe` binary uses `os.getenv()` only — it does **not** parse `.env` at startup. Setting `HINDSIGHT_API_*` variables in the repo's `.env` file has zero effect unless your launcher exports them first.

**Right way:** set the variables inline in the launcher (`.bat` `set` lines, or PowerShell `$env:`) before invoking `hindsight-api.exe`. The included `restart-hindsight.bat` ships with a minimal subset and **does not set embedder/reranker/vector_extension by default** — you have to add those.

A working PowerShell launcher template is in [Step 4](#step-4-update-the-launcher) below.

### 3. `.bat` files MUST have CRLF line endings

LF-only line endings on `.bat` files cause CMD to eat the first character of every line ("etlocal" instead of "setlocal"). After editing a `.bat` from any non-Windows tool (or via certain editors), convert to CRLF:

```powershell
$f = 'G:\hindsight-local\restart-hindsight.bat'
$content = [System.IO.File]::ReadAllText($f)
$crlfContent = $content -replace "(?<!`r)`n", "`r`n"
[System.IO.File]::WriteAllText($f, $crlfContent, [System.Text.Encoding]::ASCII)
```

### 4. Hindsight refuses dim/extension change with populated data

Two startup checks block migrating populated tables:

- `ensure_embedding_dimension`: refuses to change `vector(384)` → `vector(1024)` if the column has any non-null embeddings
- `ensure_vector_extension`: refuses to change HNSW (pgvector) → vchordrq (vchord) if `WHERE embedding IS NOT NULL` returns rows

Both checks pass once embeddings are NULL'd. The `ALTER COLUMN ... USING NULL` step in [Step 3](#step-3-prep-the-database) handles both at once.

### 5. The label allowlist drops LLM-generated rich labels by default

Per-bank entity_labels in `banks.config.entity_labels` JSON default to `type: "value"` — closed enum. If your LLM generates labels like `mood:frustrated` or `type:self-doubt` that aren't in the allowlist, Hindsight logs `Label 'X' not in valid label values, skipping` and silently drops them.

**Fix** (optional, only if you want free-form labels): see [Step 7](#step-7-optional-free-form-labels) below.

### 6. RTX 5080 / Blackwell + Optimus has a constant-GPU + concurrent-network IRQ kernel hang

In-process GPU torch with constant-GPU compute pattern (e.g., Hindsight's prior cu130 attempt) has been observed to hang the entire Windows host on this hardware. ComfyUI's bursty pattern (compute per request, idle between) works fine on the same machine.

**Implication:** don't try to move the embedder back to in-process GPU torch in Hindsight. Use Ollama as a separate process. Ollama's per-request bursty pattern is closer to ComfyUI than to constant-GPU torch and works correctly on this hardware.

---

## Pre-flight

### Build + install vchord

Follow [`WINDOWS_BUILD.md`](./WINDOWS_BUILD.md) and run [`install-and-prep-vchord-ADMIN.cmd`](./install-and-prep-vchord-ADMIN.cmd) to install. Confirm:

```sql
SELECT extname FROM pg_extension WHERE extname IN ('vector', 'vchord');
```

You should see both. The `vector` (pgvector) extension is what Hindsight currently uses. `vchord` will become the active one once we wire it in.

### Pull the embedding model into Ollama

Start Ollama via your launcher (the install path is typically `G:\ollama\start-ollama.bat` if you've moved models off C:). Make sure `OLLAMA_MODELS` is set to your preferred location BEFORE pulling — by default it lands in `%USERPROFILE%\.ollama\models` regardless of your env var unless the daemon was started with that var set.

Pull the model:

```cmd
ollama pull qwen3-embedding:0.6b
```

Verify:

```cmd
curl -s -X POST http://localhost:11434/v1/embeddings -H "Content-Type: application/json" -d "{\"model\":\"qwen3-embedding:0.6b\",\"input\":\"test\"}"
```

You should get a 1024-dim vector back. If you get an error, the model isn't pulled or Ollama isn't running on port 11434.

### Take a full pg_dump

Before any DB changes:

```cmd
"C:\Program Files\PostgreSQL\17\bin\pg_dump.exe" -Fc -d "postgresql://postgres@localhost:5432/hindsight" -f "G:\hindsight-local\backups\hindsight-pre-1024dim.dump"
```

Custom format (`-Fc`) is compressed. A 50K-row Hindsight DB compresses to ~700 MB. Restorable via `pg_restore`. **Don't skip this** — the migration nulls all embeddings before refilling, and if anything goes wrong mid-flight you want a clean rollback point.

### Install the PR #1258 branch (for the `reindex-embeddings` command — though we won't actually use its embedder path)

The command is useful for column discovery, dry-run counting, and recall verification even if we bypass its embedder. From the source repo:

```powershell
cd G:\hindsight-local\hindsight-api-slim
git checkout feat/reindex-embeddings-clean
uv pip install --python G:\hindsight-local\hindsight-api-slim\.venv\Scripts\python.exe -e .
```

Verify the new subcommand exists:

```powershell
& "G:\hindsight-local\hindsight-api-slim\.venv\Scripts\hindsight-admin.exe" reindex-embeddings --help
```

---

## Migration workflow

### Step 1 — Stop Hindsight

```powershell
Get-Process | Where-Object { $_.Path -match "hindsight-api\.exe" } | Stop-Process -ErrorAction SilentlyContinue
```

Confirm port 8888 is free:

```powershell
Get-NetTCPConnection -LocalPort 8888 -ErrorAction SilentlyContinue
```

### Step 2 — Take the pg_dump

(See pre-flight above. If you skipped it, do it now.)

### Step 3 — Prep the database

This is the irreversible-without-rollback step. Drop the old HNSW index, change the column type, and NULL all existing embeddings in one transaction:

```sql
BEGIN;

DROP INDEX IF EXISTS idx_memory_units_embedding;

ALTER TABLE memory_units ALTER COLUMN embedding TYPE vector(1024) USING NULL;
ALTER TABLE mental_models ALTER COLUMN embedding TYPE vector(1024) USING NULL;

-- sanity check
SELECT 'memory_units' AS tbl,
       format_type(atttypid, atttypmod) AS col_type,
       (SELECT COUNT(*) FROM memory_units) AS total_rows,
       (SELECT COUNT(*) FROM memory_units WHERE embedding IS NOT NULL) AS non_null
FROM pg_attribute WHERE attrelid = 'memory_units'::regclass AND attname = 'embedding'
UNION ALL
SELECT 'mental_models',
       format_type(atttypid, atttypmod),
       (SELECT COUNT(*) FROM mental_models),
       (SELECT COUNT(*) FROM mental_models WHERE embedding IS NOT NULL)
FROM pg_attribute WHERE attrelid = 'mental_models'::regclass AND attname = 'embedding';

COMMIT;
```

You should see both tables now `vector(1024)` with `non_null = 0`. If `non_null > 0`, the ALTER didn't fully apply — investigate before continuing.

### Step 4 — Update the launcher

Add the embedder + vchord + RRF reranker env vars to whichever launcher you actually use. PowerShell template (saves as `start-hindsight-ollama.ps1`):

```powershell
$envVars = @{
    'PYTHONIOENCODING' = 'utf-8'
    'HINDSIGHT_API_LLM_PROVIDER' = 'minimax'
    'HINDSIGHT_API_LLM_API_KEY' = '<your minimax key>'
    'HINDSIGHT_API_LLM_MODEL' = 'MiniMax-M2.7'
    'HINDSIGHT_API_LLM_BASE_URL' = 'https://api.minimax.io/v1'
    'HINDSIGHT_API_DATABASE_URL' = 'postgresql://postgres@localhost:5432/hindsight'

    # Embedder via Ollama (1024-dim qwen3)
    'HINDSIGHT_API_EMBEDDINGS_PROVIDER' = 'openai'
    'HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL' = 'http://localhost:11434/v1'
    'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL' = 'qwen3-embedding:0.6b'
    'HINDSIGHT_API_EMBEDDINGS_OPENAI_API_KEY' = 'ollama-no-auth'
    'HINDSIGHT_API_EMBEDDINGS_OPENAI_BATCH_SIZE' = '32'

    # Use vchord (the windows port from this repo)
    'HINDSIGHT_API_VECTOR_EXTENSION' = 'vchord'

    # RRF reranker (no neural cross-encoder = no CPU torch firing per recall)
    'HINDSIGHT_API_RERANKER_PROVIDER' = 'rrf'

    # Disable consolidation worker reservations (bursty CPU control)
    'HINDSIGHT_API_WORKER_CONSOLIDATION_MAX_SLOTS' = '0'
}

foreach ($kv in $envVars.GetEnumerator()) {
    Set-Item "env:$($kv.Key)" $kv.Value
}

Set-Location 'G:\hindsight-local\hindsight-api-slim'
& '.venv\Scripts\hindsight-api.exe' --host 127.0.0.1 --port 8888 --log-level info
```

Launch via:

```powershell
Start-Process powershell -ArgumentList @("-NoExit","-ExecutionPolicy","Bypass","-File","G:\hindsight-local\start-hindsight-ollama.ps1") -WindowStyle Normal
```

### Step 5 — Confirm Hindsight booted with vchordrq

Hindsight should boot cleanly: dim mismatch is gone (column is now 1024), extension mismatch is gone (no rows have non-null embeddings, so the data check returns 0). Hindsight will create the new vchordrq index automatically:

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'memory_units';
```

Expected output:

```
idx_memory_units_embedding | CREATE INDEX idx_memory_units_embedding ON public.memory_units USING vchordrq (embedding vector_l2_ops)
```

If you see `vchordrq` in the indexdef — **vchord is live**. The startup logs in the launcher window will also show:

```
INFO - hindsight_api.engine.embeddings - Embeddings: OpenAI provider initialized (model: qwen3-embedding:0.6b, dim: 1024)
INFO - hindsight_api.engine.cross_encoder - Reranker: RRF passthrough provider initialized (neural reranking disabled)
```

### Step 6 — Run the direct-Ollama reindex script

**Do NOT run `hindsight-admin reindex-embeddings`** — see [Gotcha 1](#1-hindsight-admin-reindex-embeddings-is-hardcoded-to-local-sentence-transformers).

Use the helper script at [`reindex-via-ollama.py`](./reindex-via-ollama.py) instead:

```powershell
& "G:\hindsight-local\hindsight-api-slim\.venv\Scripts\python.exe" "G:\projects\grimmjoww-vchord-windows-port\reindex-via-ollama.py"
```

Throughput on RTX 5080 mobile: ~12 rows/sec, ~70 min for 50K rows. CPU stays under 10%, GPU bursty around 30-50%, no thermal events. The script is resumable — if you stop it, restarting picks up the remaining NULL rows.

You can also run the script while Hindsight is up and serving live writes — they don't conflict, since Hindsight's own write path goes through the same Ollama endpoint and the script only touches NULL-embedding rows.

### Step 7 — (optional) Free-form labels

If your LLM generates rich labels that the bank's allowlist rejects, switch the affected groups to `type: "text"`:

```sql
UPDATE banks
SET config = jsonb_set(
    config,
    '{entity_labels}',
    (SELECT jsonb_agg(elem || '{"type": "text"}'::jsonb)
     FROM jsonb_array_elements(config->'entity_labels') elem)
)
WHERE bank_id IN ('your-bank', 'your-other-bank');
```

This affects future retains only — past memories that lost labels won't be retrofitted. Reversible by removing the `type` field.

---

## Validation

After the reindex completes:

```sql
SELECT 'memory_units' AS tbl,
       COUNT(*) AS total,
       COUNT(embedding) AS embedded,
       COUNT(*) - COUNT(embedding) AS still_null
FROM memory_units
UNION ALL
SELECT 'mental_models', COUNT(*), COUNT(embedding), COUNT(*) - COUNT(embedding)
FROM mental_models;
```

`still_null` should be `0` for both tables.

Run a recall against any bank to verify search works at the new dim:

```bash
curl -s -X POST http://localhost:8888/v1/default/banks/<your-bank>/memories/recall \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "limit": 5}' | jq .
```

You should get back results without 5xx errors.

---

## Rollback

If anything goes wrong:

1. Stop Hindsight
2. Restore from the pg_dump:
   ```cmd
   "C:\Program Files\PostgreSQL\17\bin\pg_restore.exe" --clean --if-exists -d "postgresql://postgres@localhost:5432/hindsight" "G:\hindsight-local\backups\hindsight-pre-1024dim.dump"
   ```
3. Revert the launcher `.bat`/`.ps1` to the previous embedder + vector_extension + reranker settings
4. Restart Hindsight

The pg_dump is your safety net. Always take it before starting.

---

## Why all this is necessary on Windows specifically

The whole point of vchord-windows-port is that vchord wasn't shipping a Windows binary. Hindsight already supported vchord in `migrations.py` — the gap was just the build.

Once you have vchord installed natively, you can run any embedding dimension Hindsight supports — including the 2560-dim `Qwen/Qwen3-Embedding-4B` and 4096-dim `Qwen3-Embedding-8B` models that pgvector's HNSW caps out under at 2000.

Combined with Ollama for the embedder runtime (no Docker, no WSL2, no in-process torch hangs on Blackwell), and RRF reranker (no second torch model), the full stack stays native Windows + bursty GPU + cool CPU.

---

## License

This document, like the rest of this repo: MIT. Use it however you want.
