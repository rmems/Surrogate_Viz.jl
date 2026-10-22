# AGENTS.md

Guidance for coding agents (Amp, Codex, Cursor, Claude Code, and others) working in this repository.

## Purpose

`Surrogate_Viz.jl` is a Julia SymbolicRegression + visualization workbench for `corinth-canal` SAAQ
telemetry (see `README.md`). It consumes dual-SAAQ CSVs and tick telemetry from the Rust simulator,
plus `grok-ozempic` bundles, and produces SymbolicRegression.jl hall-of-fame discoveries and
paired-run validation dashboards. Per the README, SAAQ bundles currently come from synthetic
fixtures under `test/fixtures/bundles/` because corinth-canal integration isn't live yet.

## Layout

| Path | Contents |
|------|----------|
| `src/` | Package (`Surrogate_Viz.jl`, `backend.jl`, `kernels.jl`, `labels.jl`, `grok_ozempic.jl`, `normalizers/`) |
| `ext/CUDABackendExt.jl` | Optional CUDA backend (weak dependency) |
| `scripts/` (own `Project.toml`) | Validate/ingest SAAQ and grok-ozempic bundles, build dashboards |
| Root `*.jl` (`SAAQ_*discovery.jl`, `compare_*.jl`, `plot_*.jl`, `import_corinth_runs.jl`) | Research/driver scripts |
| `test/runtests.jl` (+ `test/fixtures/`) | Test suite |
| `outputs/` | Committed generated artifacts (CSV, PNG) |
| `Dockerfile`, `.github/RUNNER.md` | CUDA container image and self-hosted runner notes |

## Toolchain

- Julia **1.12** (`[compat] julia = "1.12"`; hosted CI job). `Manifest.toml` is gitignored.
- **GPU:** CUDA is optional (weak dependency, never installed unless you `Pkg.add("CUDA")`).
  `CUDABackend()` falls back to CPU with a warning. The GPU jobs in `julia.yml` run on self-hosted
  `gpu, sm120, julia-cuda, docker` runners. The `Dockerfile` builds on a CUDA 13.2.0 image.

## Commands (from `.github/workflows/julia.yml` and `README.md`)

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using Pkg; Pkg.test()'          # hosted CPU job

# Bundle tools
julia --project=. scripts/validate_saaq_bundle.jl test/fixtures/bundles/successful_synthetic/
julia --project=. scripts/ingest_saaq_bundles.jl test/fixtures/bundles/ /tmp/saaq_normalized/
julia --project=. scripts/validate_grok_ozempic_bundle.jl test/fixtures/grok_ozempic/pass/
julia --project=. scripts/ingest_grok_ozempic_bundles.jl test/fixtures/grok_ozempic/ /tmp/grok_normalized/
```

GPU-only (self-hosted): `Pkg.add("CUDA"); Pkg.test()` and `bash .github/scripts/run_cuda_visuals.sh`.

## Conventions visible in the repo

- One-way data flow with corinth-canal (README "Repo Separation"): imported simulator runs land
  under `data/corinth_runs/<model>/<telemetry_source>/<condition>/<run_id>/` (`IMPORT_ROOT` in
  `src/Surrogate_Viz.jl`), and generated artifacts go under `outputs/<model>/`. Simulator code
  belongs to corinth-canal, so make simulator changes there rather than here.
- The model roster is declared once in the label registry (`src/labels.jl`).
- GitHub Actions are pinned to commit SHAs. Commit subjects use Conventional Commits (`feat:`,
  `fix:`, `ci:`) with the PR number.
