# vchord-windows-port

Native Windows MSVC build documentation and helper scripts for [TensorChord/VectorChord](https://github.com/tensorchord/VectorChord) — the high-dimensional vector search Postgres extension.

This repository documents the toolchain and steps to produce a working `vchord.dll` on Windows without Docker, without WSL2. The vchord codebase already supports `x86_64-pc-windows-msvc` as a target via `xtask`; this repo just fills in the gap so anyone with PostgreSQL on Windows can reproduce the build.

## What's here

| File | What it does |
|---|---|
| `WINDOWS_BUILD.md` | Full toolchain + build + install + verification guide |
| `with-vc-env.cmd` | Wrapper that activates VS2022 + Postgres dev + LLVM env, then runs your command |
| `step-build2.cmd` | One-shot build script (calls `cargo run -p xtask --release -- build`) |
| `install-and-prep-vchord-ADMIN.cmd` | **Recommended.** One-click admin script — copies DLL + extension files, edits `postgresql.conf` to add `vchord` to `shared_preload_libraries`, restarts the Postgres service. Single UAC prompt. |
| `install-vchord.cmd` | Older simpler installer — only copies files (you handle postgresql.conf + service restart manually) |
| `uninstall-vchord.cmd` | Admin-required uninstaller — removes vchord from Postgres |
| `test-vchord.sql` | Smoke-test SQL — `CREATE EXTENSION vchord` + create vchordrq index + nearest-neighbor query |

## Verified configuration

Built end-to-end on:

- Windows 11 24H2
- Visual Studio 2022 Community (MSVC 14.44)
- LLVM 22.1.4 (clang + libclang)
- Rust 1.95.0 stable
- cargo-pgrx 0.17.0
- PostgreSQL 17.9 (EnterpriseDB installer)

Output: `vchord.dll` 9.4 MB PE32+ x64. `dumpbin /dependents` shows imports against `postgres.exe`, KERNEL32, ntdll, VCRUNTIME140, UCRT — exactly the same shape as pgvector's Windows DLL.

## Critical gotcha

**Rust 1.93 and 1.94 fail to build** with `E0658: use of unstable library feature 'stdarch_x86_avx512_f16'` in `crates/simd/src/floating_f16.rs`. Those AVX-512 FP16 intrinsics were stabilized in Rust 1.95.0. After `rustup update`, the build is clean.

## Quick start

See [`WINDOWS_BUILD.md`](./WINDOWS_BUILD.md) for the full guide.

## Status & maintenance

Lazily maintained — these are documentation + helper scripts for an existing build path that already works in the upstream codebase. If a future vchord release breaks the steps documented here, expect a patch within a week or two of me noticing. PRs welcome for: pg version bumps, alternative MSVC toolchains, ARM64 Windows, automation tooling. MIT license — fork freely if you need faster turnaround.

## Using vchord with Hindsight on Windows

If you're running [vectorize-io/hindsight](https://github.com/vectorize-io/hindsight) on Windows and want to use embedding models above pgvector's 2000-dim HNSW limit (e.g. `Qwen/Qwen3-Embedding-4B` at 2560 dim), vchord is your unlock — `vchordrq` indexes have no such ceiling.

Hindsight already supports vchord natively in its migration logic (`migrations.py` switches index creation to `vchordrq` when the vchord extension is detected). The only piece missing on Windows was the build itself — which is what this repo provides.

Workflow:

1. Build vchord using the steps in [`WINDOWS_BUILD.md`](./WINDOWS_BUILD.md)
2. Install via `install-vchord.cmd` (admin)
3. In your Hindsight `.env` or environment:
   ```
   HINDSIGHT_API_VECTOR_EXTENSION=vchord
   ```
4. Restart Hindsight. It will use vchordrq indexes for any embedding column ≥ 0 dimensions — no 2000 cap.
5. Re-embed existing data with the [`reindex-embeddings`](https://github.com/vectorize-io/hindsight/pull/1258) admin command (also covers `halfvec` columns):
   ```
   hindsight-admin reindex-embeddings --auto-backup ./pre-reembed.zip --verify-recall --yes
   ```

This combination — vchord on Windows + Hindsight — is the only way as of April 2026 to run Qwen3-Embedding-4B (2560-dim) or 8B (4096-dim) on Hindsight without leaving Windows for Linux/Docker/WSL2.

## License (this repo)

MIT — these are my notes, scripts, and documentation of an existing build process. Use them however you like.

The vchord source code itself is **NOT** in this repo. vchord is dual-licensed AGPL-3.0 / Elastic License v2 by TensorChord — get it from [their official repo](https://github.com/tensorchord/VectorChord).

## Why this is a separate repo (not an upstream PR)

I attempted to contribute these docs upstream as [PR #455](https://github.com/tensorchord/VectorChord/pull/455). Closing it after reading TensorChord's CLA, which grants them the right to "license Your Contributions under any license, including but not limited to copyleft, permissive, commercial, or proprietary license" and to "change or modify the license applied... from time to time."

I publish my work open. I'm not comfortable signing a precedent that lets anyone relicense my contributions as proprietary later. That's a personal stance, not a value judgment on TensorChord's project — vchord itself is excellent technology and the build worked beautifully.

These docs remain here for the community. If anyone at TensorChord wants to incorporate the content into the official repo, please rewrite it under your own CLA — it documents an existing build path, not novel IP.
