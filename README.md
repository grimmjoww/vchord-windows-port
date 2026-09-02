# vchord-windows-port

> A verified Windows-native build and migration path for TensorChord/VectorChord and Hindsight—without Docker or WSL2.

This repository documents and automates the missing Windows operator experience around [TensorChord/VectorChord](https://github.com/tensorchord/VectorChord), a high-dimensional vector-search extension for PostgreSQL.

The upstream project already contains the `x86_64-pc-windows-msvc` target. This repository supplies the reproducible toolchain notes, helper scripts, installation steps, smoke tests, and Hindsight migration guidance needed to turn that target into a working Windows deployment.

## What was verified

The documented process produced a working `vchord.dll` and exercised extension creation and nearest-neighbor indexing on Windows.

Verified environments include:

- Windows 11 24H2
- Visual Studio 2022 Community / MSVC 14.44
- LLVM 22.1.4
- Rust 1.95.0 stable
- `cargo-pgrx` 0.17.0
- PostgreSQL 17.9 with `tensorchord/VectorChord@main`
- PostgreSQL 18.3 with `tensorchord/VectorChord@1.1.1`

The resulting DLL was a 64-bit Windows binary linked against the expected PostgreSQL and Windows runtime dependencies.

## Repository map

| File | Purpose |
|---|---|
| `WINDOWS_BUILD.md` | Full toolchain, build, installation, and verification guide. |
| `HINDSIGHT-1024DIM-UPGRADE.md` | End-to-end Hindsight migration playbook, including reindex and environment gotchas. |
| `reindex-via-ollama.py` | Resumable direct-Ollama reindex helper for the upstream local-transformer limitation encountered during migration. |
| `with-vc-env.cmd` | Activates the Visual Studio, PostgreSQL, and LLVM build environment before running a command. |
| `step-build2.cmd` | Runs the release build through the upstream `xtask` path. |
| `install-and-prep-vchord-ADMIN.cmd` | Copies extension files, updates `shared_preload_libraries`, and restarts PostgreSQL with one elevation flow. |
| `install-vchord.cmd` | Simpler copy-only installer for operators who want to configure PostgreSQL manually. |
| `uninstall-vchord.cmd` | Removes the installed Windows extension files. |
| `test-vchord.sql` | Smoke test for extension creation, index creation, and nearest-neighbor lookup. |

## The important build failure

Rust 1.93 and 1.94 failed in the SIMD code with the unstable `stdarch_x86_avx512_f16` feature. Those intrinsics were available on the tested path with Rust 1.95.0. Updating the toolchain resolved the build failure.

That version boundary is documented because it is exactly the sort of issue that turns a supposedly supported target into an afternoon of unexplained compiler errors.

## Quick start

1. Follow [`WINDOWS_BUILD.md`](./WINDOWS_BUILD.md) to install the required MSVC, LLVM, Rust, `cargo-pgrx`, and PostgreSQL development components.
2. Build the matching upstream VectorChord revision.
3. Install the extension with `install-and-prep-vchord-ADMIN.cmd`, or use the copy-only installer and configure PostgreSQL manually.
4. Run [`test-vchord.sql`](./test-vchord.sql).
5. For a populated Hindsight system, follow [`HINDSIGHT-1024DIM-UPGRADE.md`](./HINDSIGHT-1024DIM-UPGRADE.md) instead of changing the vector extension or dimensions ad hoc.

## Hindsight integration

Hindsight can create `vchordrq` indexes when the VectorChord extension is available. For a fresh installation, the high-level path is straightforward: install the extension, select it in Hindsight's runtime configuration, and restart.

A populated installation is more delicate. Operators may encounter:

- embedding-dimension mismatch safeguards;
- vector-extension mismatch safeguards;
- environment variables not being loaded by the launcher they expected;
- an upstream reindex command using local sentence-transformers instead of the configured Ollama endpoint;
- GPU-selection and model-serving details on Windows laptops.

The migration guide and `reindex-via-ollama.py` document the tested workaround and verification path.

## Evidence and portfolio value

This project demonstrates:

- Windows-native build troubleshooting across MSVC, LLVM, Rust, `pgrx`, and PostgreSQL;
- reproducible installation and removal scripts;
- a real database smoke test rather than a build-only claim;
- migration planning for an existing AI memory system;
- documented failure modes and recovery steps;
- practical integration between Postgres vector search, Hindsight, Ollama, and GPU-served embeddings.

The work was completed through an AI-assisted engineering workflow directed by **Willie Stewart / Phantom Horizon Studios**, including requirements definition, agent direction, environment diagnosis, test execution, failure investigation, and documentation review.

## Status and maintenance

This is a narrowly scoped documentation-and-tooling project for an upstream build path. It is maintained as needed rather than on a release schedule. Verify the upstream VectorChord, Rust, PostgreSQL, and Hindsight versions before treating the documented matrix as current.

## Provenance and licensing

The VectorChord source is **not** copied into this repository. It remains governed by TensorChord's licenses. The documentation and helper scripts in this repository are MIT-licensed.

An upstream documentation contribution was considered and later closed after review of the contributor agreement. These notes remain independently published so the Windows build path can stay openly accessible without changing upstream ownership or licensing.

## Related

- [TensorChord/VectorChord](https://github.com/tensorchord/VectorChord)
- [vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)
- [grimmjoww/hindsight-installer-mcp](https://github.com/grimmjoww/hindsight-installer-mcp)
