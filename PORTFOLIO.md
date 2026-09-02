# Native Windows VectorChord Integration

## The Problem

VectorChord gives PostgreSQL a high-dimensional vector index, but the practical Windows path was poorly documented. Running it natively meant assembling the correct MSVC, LLVM, Rust, `cargo-pgrx`, and PostgreSQL toolchain, then working through failures that looked like project bugs but were actually version and environment mismatches.

The problem became more involved when VectorChord was used to upgrade an existing Hindsight memory installation. Changing the embedding model also meant changing vector dimensions, installing the extension, migrating existing rows, and confirming that recall still worked.

## Constraints

The target workflow needed to work:

- on native Windows without Docker or WSL2
- against an installed PostgreSQL instance
- with reproducible toolchain versions
- with an existing Hindsight database, not only a clean demo
- with GPU-served Ollama embeddings instead of forcing a large local transformer workload onto the CPU
- with installation, rollback, and verification steps a user or agent could follow

## Approach

The repository separates the work into focused pieces:

- a full Windows build guide
- environment wrappers for Visual Studio, PostgreSQL, LLVM, and Rust
- repeatable build and installation scripts
- an uninstall path
- a SQL smoke test for extension creation, index creation, and nearest-neighbor search
- a validated Hindsight migration playbook
- a resumable direct-Ollama reindex helper

The result is not a custom fork of VectorChord. It is a reproducible Windows integration layer around the upstream project.

## Failure Diagnosis

One of the key build failures came from Rust 1.93 and 1.94 reporting an unstable `stdarch_x86_avx512_f16` feature in VectorChord’s SIMD code. The underlying intrinsics were stabilized in Rust 1.95. Updating the toolchain resolved the build without patching upstream source.

The Hindsight migration exposed a separate issue: its administrative reindex command used a local sentence-transformers path instead of honoring the configured Ollama embedding service. The repository includes a direct-Ollama reindex helper so the migration can use the GPU-backed endpoint and resume instead of restarting the full job after an interruption.

## Automation and Helper Scripts

The repository includes scripts for:

- activating the required Windows build environment
- building VectorChord through the upstream `xtask` flow
- copying extension files into PostgreSQL
- updating `shared_preload_libraries`
- restarting the PostgreSQL service
- uninstalling the extension
- running a vector-index smoke test
- re-embedding Hindsight rows through Ollama

These scripts reduce the amount of fragile manual work while keeping the individual operations visible and reversible.

## Validated Configuration

The documented build was validated on Windows 11 with Visual Studio 2022, LLVM 22.1.4, Rust 1.95.0, `cargo-pgrx` 0.17.0, and PostgreSQL 17.9 or 18.3 as listed in the repository README.

The status claim is deliberately narrow: **validated on the stated Windows and PostgreSQL configurations**. It is not a guarantee that every release, compiler, or machine will behave identically.

## Result

The workflow produced a native x64 `vchord.dll`, verified its runtime dependencies, installed the extension into PostgreSQL, created a `vchordrq` index, and supported a Hindsight migration to a larger embedding pipeline without requiring Linux, Docker, or WSL2.

## My Contribution

I directed and verified the integration work: defining the native-Windows constraint, diagnosing toolchain failures, organizing the build and install workflow, requiring smoke tests and rollback paths, testing the Hindsight migration, and turning the discovered failure modes into scripts and documentation other users can follow.

The implementation was completed through an AI-assisted engineering workflow with human review of commands, diffs, test results, service behavior, and final documentation.

## Why This Matters to a Client

This case study shows how I handle systems work where several components are individually documented but the complete workflow is not. I trace the actual failure, separate upstream behavior from integration problems, build repeatable tooling around the gap, and document the conditions under which the result was verified.
