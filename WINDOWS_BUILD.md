# Building VectorChord on Windows (Native, MSVC)

> **Status:** First-known successful native Windows MSVC build.
> Built locally on 2026-04-25 from `tensorchord/VectorChord@main` for PostgreSQL 17 with no source-code changes. PostgreSQL 18 verified on 2026-05-02 from `tensorchord/VectorChord@1.1.1` with the same toolchain — only difference: vchord 1.1.1 added a `cshim/x86_64_fp16.c` that requires Clang (not MSVC), so set `CC=clang.exe` for the `cc` crate. See "Pitfalls encountered" below.
> Outputs a textbook PE32+ Windows DLL that links against `postgres.exe` import library, exactly like pgvector does on Windows.

## Pull location

Always clone fresh from upstream — no fork needed, this repo doesn't track vchord source:

```cmd
git clone https://github.com/tensorchord/VectorChord
cd VectorChord
git checkout v1.1.1
```

Upstream `v1.1.1` (Feb 2026) supports PostgreSQL **14, 15, 16, 17, and 18** in source. Upstream ships Linux binaries for all five but no Windows binaries — that's the gap this repo fills.

## Result

- **Output DLL:** `vchord.dll` — 9.4 MB, PE32+ x64
- **Extension SQL:** `vchord--0.0.0.sql` (1323 lines, all types: `vector`, `halfvec`, `rabitq4`, `rabitq8`, `sphere_*`)
- **Build time:** ~2 minutes on a 5080-class workstation (release profile)
- **No source changes required** — the codebase already supports `x86_64-pc-windows-msvc` as a cargo target. Upstream ships only Linux artifacts because no Windows runner is in their CI matrix.

## Required toolchain

| Component | Version | Why |
|---|---|---|
| **Rust** | **1.95.0+ (stable)** | The `simd` crate uses AVX-512 FP16 intrinsics (`stdarch_x86_avx512_f16`). These were unstable in 1.93; stabilized in 1.95. **1.93 will not build.** |
| **MSVC C/C++ Build Tools** | VS2022 17.x (any) | C compilation for `cc` crate dependencies + linker |
| **LLVM / clang** | 16+ (22.1.4 tested) | `pgrx-pg-sys` uses `bindgen` which requires `libclang.dll`. Set `LIBCLANG_PATH` to the bin dir. |
| **PostgreSQL 17 or 18 dev install** | 17.9 + 18.3 tested | Provides `pg_config.exe`, headers in `include/server/`, and `postgres.lib` import library. Same recipe — pick the version you want vchord to bind against. |
| **cargo-pgrx** | **0.17.0** (must match `pgrx` pin in `Cargo.toml`) | Build orchestration. `cargo install --locked cargo-pgrx@0.17.0` |

## Build steps

```cmd
:: 1. Activate VS2022 build env in your shell
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

:: 2. Add Postgres + LLVM bin to PATH
set "PATH=C:\path\to\llvm\bin;C:\Program Files\PostgreSQL\17\bin;%PATH%"
set "LIBCLANG_PATH=C:\path\to\llvm\bin"

:: 3. Initialize pgrx (one-time, points at your existing PG install)
cargo pgrx init --pg17 "C:\Program Files\PostgreSQL\17\bin\pg_config.exe"
:: For PG 18: cargo pgrx init --pg18 "C:\Program Files\PostgreSQL\18\bin\pg_config.exe"

:: 4. Build vchord
set "PG_CONFIG=C:\Program Files\PostgreSQL\17\bin\pg_config.exe"
:: For PG 18: set "PG_CONFIG=C:\Program Files\PostgreSQL\18\bin\pg_config.exe"
cargo run -p xtask --release -- build

:: Output goes to:
::   .\build\pkglibdir\vchord.dll
::   .\build\sharedir\extension\vchord--<version>.sql
::   .\build\sharedir\extension\vchord.control
```

## Install

Windows Postgres extensions live in the same place pgvector goes:

```cmd
:: REQUIRES ADMIN
copy /Y .\build\pkglibdir\vchord.dll                    "C:\Program Files\PostgreSQL\17\lib\"
copy /Y .\build\sharedir\extension\vchord--*.sql        "C:\Program Files\PostgreSQL\17\share\extension\"
copy /Y .\build\sharedir\extension\vchord.control       "C:\Program Files\PostgreSQL\17\share\extension\"
```

Edit `C:\Program Files\PostgreSQL\17\data\postgresql.conf` and add `vchord` to `shared_preload_libraries`:

```
shared_preload_libraries = 'vchord'
```

Restart Postgres:

```cmd
net stop postgresql-x64-17
net start postgresql-x64-17
```

In psql:

```sql
CREATE EXTENSION vchord CASCADE;
```

## DLL imports verified (sanity check)

`dumpbin /dependents vchord.dll` shows exactly the expected set:

- `postgres.exe` ← extension symbols imported from running Postgres binary (correct on Windows)
- `KERNEL32.dll`, `ntdll.dll` ← OS
- `VCRUNTIME140.dll`, `api-ms-win-crt-*` ← MSVC + Universal C Runtime
- `bcryptprimitives.dll` ← Windows crypto

No Linux `.so`, no missing imports, no surprises.

## Pitfalls encountered

1. **Rust 1.93 fails with E0658 on `stdarch_x86_avx512_f16`.** AVX-512 FP16 intrinsics in `crates/simd/src/floating_f16.rs:2014+` need stable Rust 1.95+. Just `rustup update`.
2. **`cargo pgrx init` requires an existing Postgres install on Windows.** pgrx doesn't auto-download Postgres on Windows the way it does on Linux/macOS. Use the EnterpriseDB installer for Postgres 17 first, then point `cargo pgrx init --pg17` at its `pg_config.exe`.
3. **xtask requires `PG_CONFIG` env var** — set it before `cargo run -p xtask`. The Linux Makefile sets this; Windows users must do it manually.
4. **vcvars64.bat env doesn't propagate into bash sessions on Windows.** Use a `.cmd` wrapper that calls vcvars64 then runs your command, or run from a "x64 Native Tools Command Prompt for VS 2022" directly.
5. **vchord 1.1.1+ requires Clang for C shim files.** vchord 1.1.1 added `cshim/x86_64_fp16.c` which contains `#error "This file requires Clang or GCC."` — the `cc` crate defaults to MSVC's `cl.exe` after `vcvars64`, which fails. Set `CC=clang.exe` and `CC_x86_64_pc_windows_msvc=clang.exe` in your env wrapper before running the build. Affects PG 18 builds (since 1.1.1 is the first release with PG 18 support); also affects PG 17 builds against 1.1.1+. The 0.0.0 / pre-1.1.0 source did not have this dependency.
6. **vchord 1.1.1 depends on pgvector being installed first.** `CREATE EXTENSION vchord CASCADE` requires the `vector` extension. On Windows that means building pgvector separately via its `nmake /F Makefile.win` flow against the same PG version. Trivial build (~1 min), but it's now a hard prerequisite.

## Suggested upstream changes for first-class Windows support

Upstream `v1.1.1` ships Linux binaries for PG 14, 15, 16, 17, and 18 — but still no Windows binaries. The gap this repo fills.

1. Add a Windows runner to `.github/workflows/release.yml` to publish `vchord-pg{17,18}-x86_64-windows-msvc.zip` artifacts alongside the existing Linux deb/zip outputs.
2. Document the build process (this file → `docs/installation/windows.md`).
3. (Optional) Wrap `make build` in a PowerShell script for Windows users who don't have GNU make.
