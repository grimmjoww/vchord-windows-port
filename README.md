# VectorChord Windows Port

**A reproducible native Windows build and migration path for TensorChord/VectorChord—without Docker or WSL2.**

VectorChord is a high-dimensional vector-search extension for Postgres. Its upstream source already contains an MSVC target, but the practical Windows path still involves several moving pieces: Rust and `pgrx` versions must match, Postgres development files must be available, Clang has to handle the newer C shim, the resulting DLL must land in the right server directories, and Hindsight needs a coordinated index and embedding migration if data already exists.

This repository records the complete path that worked, packages the repetitive parts into helper scripts, and includes a separate Hindsight migration playbook for moving a populated memory system onto vchord.

## What was verified

Two native builds were completed locally:

| Target | Upstream source | Verified date | Toolchain notes |
|---|---|---:|---|
| PostgreSQL 17.9 | `tensorchord/VectorChord@main` | April 25, 2026 | Native MSVC build with no source-code changes |
| PostgreSQL 18.3 | `tensorchord/VectorChord@1.1.1` | May 2, 2026 | Same overall process, with Clang selected for the added FP16 C shim |

The verified environment included:

- Windows 11 24H2
- Visual Studio 2022 Community / MSVC 14.44
- LLVM 22.1.4
- Rust 1.95.0 stable
- `cargo-pgrx` 0.17.0
- PostgreSQL 17.9 and 18.3

The build produced a 9.4 MB `vchord.dll` PE32+ x64 binary. `dumpbin /dependents` showed the expected Windows and Postgres imports, including `postgres.exe`, the MSVC runtime, and Windows system libraries.

Those versions describe the configurations that were actually exercised. They are not a promise that every later VectorChord, Rust, `pgrx`, or PostgreSQL release will work unchanged.

## What is in this repository

| File | Purpose |
|---|---|
| [`WINDOWS_BUILD.md`](./WINDOWS_BUILD.md) | Full native toolchain, build, install, and verification guide |
| [`HINDSIGHT-1024DIM-UPGRADE.md`](./HINDSIGHT-1024DIM-UPGRADE.md) | End-to-end Hindsight migration playbook for moving an existing installation to a larger Ollama-served embedding model on vchord |
| [`reindex-via-ollama.py`](./reindex-via-ollama.py) | Resumable direct-Ollama reindex helper for the upstream reindex path that ignored the configured Ollama provider at the time of testing |
| [`with-vc-env.cmd`](./with-vc-env.cmd) | Opens the Visual Studio, Postgres, and LLVM build environment before running a command |
| [`step-build2.cmd`](./step-build2.cmd) | Small wrapper for the upstream `xtask` release build |
| [`install-and-prep-vchord-ADMIN.cmd`](./install-and-prep-vchord-ADMIN.cmd) | Copies the extension files, updates `shared_preload_libraries`, and restarts the Postgres service with one elevated run |
| [`install-vchord.cmd`](./install-vchord.cmd) | Simpler file-copy installer for users who prefer to update Postgres configuration themselves |
| [`uninstall-vchord.cmd`](./uninstall-vchord.cmd) | Removes the installed vchord files from system Postgres |
| [`test-vchord.sql`](./test-vchord.sql) | Smoke-test SQL for extension creation, index creation, and a nearest-neighbor query |

The repository does **not** redistribute the VectorChord source or a prebuilt DLL. It documents and automates a build against the upstream project.

## Why the Windows build is easy to get wrong

The final command is simple:

```cmd
cargo run -p xtask --release -- build
```

Getting the environment into a state where that command succeeds is the actual work.

The verified path requires:

1. An installed PostgreSQL development environment with `pg_config.exe`, server headers, and `postgres.lib`.
2. A Visual Studio x64 native build shell or an equivalent `vcvars64.bat` wrapper.
3. LLVM/Clang and a valid `LIBCLANG_PATH` for `bindgen`.
4. The `cargo-pgrx` version that matches VectorChord's pinned `pgrx` dependency.
5. `PG_CONFIG` pointed at the exact PostgreSQL version being targeted.
6. For VectorChord 1.1.1 and newer source containing `cshim/x86_64_fp16.c`, `CC=clang.exe` and `CC_x86_64_pc_windows_msvc=clang.exe`.
7. A matching Windows installation of pgvector before `CREATE EXTENSION vchord CASCADE` when the selected VectorChord release depends on it.

The full commands and paths are in [`WINDOWS_BUILD.md`](./WINDOWS_BUILD.md).

## Important version trap

Rust 1.93 and 1.94 failed against the tested source with:

```text
E0658: use of unstable library feature 'stdarch_x86_avx512_f16'
```

The required AVX-512 FP16 intrinsics were available on stable Rust 1.95.0. Updating the Rust toolchain resolved the failure in the verified environment.

That is a concrete finding from the tested versions, not a general rule for all future VectorChord releases. When reproducing the build, start from the versions in the matrix above and change one dependency at a time.

## High-level build and verification flow

```text
Install PostgreSQL dev files, VS2022, LLVM, Rust, and matching cargo-pgrx
        ↓
Initialize pgrx against the target pg_config.exe
        ↓
Set PG_CONFIG, LIBCLANG_PATH, and—when required—the Clang CC variables
        ↓
Build through VectorChord's upstream xtask
        ↓
Copy the DLL, SQL, and control files into the matching Postgres installation
        ↓
Add vchord to shared_preload_libraries and restart Postgres
        ↓
Run test-vchord.sql and inspect the DLL dependencies
```

The helper scripts reduce typing, but the documentation remains the source of truth. Read the paths before running an elevated installer; system Postgres locations vary by version and installation method.

## Using the build with Hindsight

The practical reason this work started was Hindsight. Larger embedding models can exceed the dimensions supported by the pgvector HNSW configuration used in that setup, while Hindsight already contains a vchord-aware migration path.

For a fresh Hindsight installation, the workflow is comparatively small: install vchord, configure Hindsight to use it, select the embedding model and dimension, then start with an empty database.

A populated installation is different. It may involve:

- A changed embedding dimension
- A different vector-extension type
- Existing rows that must be re-embedded
- Hindsight startup safeguards that reject a mismatched schema
- Environment values supplied by the launcher rather than automatically loaded from `.env`
- Verification that retrieval still finds the expected memories after migration

[`HINDSIGHT-1024DIM-UPGRADE.md`](./HINDSIGHT-1024DIM-UPGRADE.md) records the complete migration used for the tested system, including backup steps, schema changes, reindexing through Ollama, and post-migration checks.

For an agent-callable version of that operational workflow, see [`hindsight-installer-mcp`](https://github.com/grimmjoww/hindsight-installer-mcp).

## Reindex helper

At the time this migration was performed, Hindsight's administrative reindex command initialized a local sentence-transformers path instead of honoring the configured Ollama embedding provider. [`reindex-via-ollama.py`](./reindex-via-ollama.py) was created as a direct, resumable workaround.

On the tested RTX 5080 mobile system, the script processed roughly 12 rows per second. That number is included as one observed result, not a benchmark guarantee; throughput depends on the model, hardware, database, and record sizes.

Because upstream behavior can change, check the current Hindsight implementation before assuming the workaround is still required.

## Project status

**Community documentation and helper tooling for a verified build path.**

This is not an official TensorChord Windows distribution, a managed installer, or a promise of compatibility with untested releases. It is maintained as a practical reference for the versions and environments documented here. Reproducible reports and pull requests for newer PostgreSQL releases, alternate toolchains, ARM64, or improved automation are welcome.

## Provenance and licensing

The documentation, helper scripts, and migration notes in this repository are released under the MIT License.

VectorChord itself is an upstream TensorChord project and is not included here. Its source carries its own AGPL-3.0 / Elastic License v2 terms; obtain it from the [official VectorChord repository](https://github.com/tensorchord/VectorChord).

An earlier version of the Windows documentation was proposed upstream in [TensorChord/VectorChord PR #455](https://github.com/tensorchord/VectorChord/pull/455). I chose not to sign the contribution agreement because of its relicensing terms, so the independently written documentation remains here. That decision concerns contribution terms, not the quality of VectorChord—the extension worked well in the tested deployment.

## Related work

- [TensorChord/VectorChord](https://github.com/tensorchord/VectorChord) — upstream extension
- [Hindsight](https://github.com/vectorize-io/hindsight) — memory engine used for the migration case
- [Hindsight Installer MCP](https://github.com/grimmjoww/hindsight-installer-mcp) — agent-facing install, migration, verification, and rollback tools
- [Phantom Horizon Studios](https://github.com/grimmjoww/phantom-horizons-studios) — related agent-systems portfolio
