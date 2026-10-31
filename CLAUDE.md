# CLAUDE.md

Detailed, verified notes for Claude Code. Shared agent guidance for other tools is in `AGENTS.md`; keep the two consistent. Project overview, usage, and bundle formats are in
`README.md`, and smoke-test commands are in `docs/validation.md`, so they are not repeated here.

## Commands

Run from the repo root. "Verified" means it ran successfully in a fresh checkout on Julia 1.12.0 (Linux, CPU only, no GPU).
`Project.toml` pins `julia = "1.12"`. The root `Manifest.toml` is gitignored (only `dev/Manifest.toml` is tracked).

| Command | Status |
|---|---|
| `julia --project=. -e 'using Pkg; Pkg.instantiate()'` | verified (about 10 min cold, mostly precompile) |
| `julia --project=. -e 'using Pkg; Pkg.test()'` | verified (all testsets pass; CUDA testset skipped without a GPU) |
| `julia --project=. scripts/validate_saaq_bundle.jl test/fixtures/bundles/successful_synthetic/` | verified |
| `julia --project=. scripts/ingest_saaq_bundles.jl test/fixtures/bundles/ <out_dir>` | verified |
| `julia --project=. scripts/build_saaq_dashboard.jl <normalized_dir> <report_dir>` | verified (on the ingest output above) |
| `julia --project=. scripts/validate_grok_ozempic_bundle.jl test/fixtures/grok_ozempic/pass/` | verified |
| `julia --project=. scripts/ingest_grok_ozempic_bundles.jl test/fixtures/grok_ozempic/ <out_dir>` | verified |
| `julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.add("CUDA")'` then `Pkg.test()` | not run (needs a CUDA GPU; the self-hosted `test` job runs it in a throwaway checkout. `Pkg.add` can edit `Project.toml`, so locally use a temporary copy of the checkout, or after the run undo only the `Pkg.add` lines in `Project.toml` (check `git diff`; a blanket `git checkout Project.toml` would also discard your own unstaged edits to it)) |
| `bash .github/scripts/run_cuda_visuals.sh` | not run (needs Docker, `--gpus all`, and the sm_120 runner) |
| `docker build .` (`docker-build.yml`) | not run (Docker not available) |

CI (`.github/workflows/julia.yml`) runs `test-cpu` on `ubuntu-latest` (Julia 1.12, instantiate, `Pkg.test()`). The `test`,
`gpu-preflight`, and `cuda-visuals` jobs need the self-hosted RTX 5080 runner and are skipped for fork PRs; they are not local gates.
There is no formatter config or lint gate in the repo.

## Architecture map

- `src/Surrogate_Viz.jl`: module definition, exports, paired-run logic; includes the files below.
- `src/backend.jl`, `src/kernels.jl`: `ComputeBackend` (`CPUBackend`/`CUDABackend`) and CPU dispatch targets.
- `ext/CUDABackendExt.jl`: package extension, loaded only when `CUDA` (a weak dependency) is present.
- `src/grok_ozempic.jl`, `src/normalizers/{SaaqNormalizer,GrokOzempicNormalizer}.jl`: bundle structs, loaders, validators, DataFrame tables.
- `src/labels.jl`: central label registry and `KNOWN_MODEL_SLUGS`.
- `scripts/`: bundle validate/ingest/dashboard CLIs (workspace member with its own `Project.toml`). Root-level `*.jl` scripts are analysis and plotting entry points.
- `test/runtests.jl` plus `smoke_scripts_test.jl` and `telemetry_provenance_test.jl`; synthetic bundles live in `test/fixtures/`.
- `dev/`: editor/LSP environment (includes CUDA); `docs/validation.md`: smoke commands; `.github/RUNNER.md`: self-hosted runner threat model.

## Invariants and non-goals

- corinth-canal is not yet ready: every SAAQ bundle comes from synthetic fixtures, and `SAAQ_discovery.jl` runs on a synthetic proxy (README "Status"). Do not present results as real SNN evidence.
- CUDA is optional: never add it to `[deps]`; it stays a weak dependency behind `CUDABackendExt`. CPU must keep working, and `CUDABackend` falls back to CPU with a warning.
- `[workspace]` lists `dev` and `scripts`; both resolve `Surrogate_Viz` through `[sources]` path `..`.
- GitHub Actions are pinned to commit SHAs with version comments. Keep self-hosted jobs behind the same-repository `if:` guard.
- `data/corinth_runs/*`, `outputs/*` (except `outputs/root_artifacts/`), `/*.csv`, `/*.json`, `/*.png`, `/*.txt` and `data/selected_runs.toml` are gitignored for new files. Some artifacts are already tracked anyway (20 files under `outputs/`, plus `data/corinth_runs/imported_runs_index.csv`), and ignore rules do not stop git from recording changes to tracked files. After a script run, check `git status` and do not commit regenerated output over them.

## Gotchas

- Source files carry no SPDX header (checked `src/`, `ext/`, `scripts/`, `test/`, and the root scripts); do not add one.
- `Project.toml` has no `exclude`/`include` list, so adding this file needs no manifest change. Never run package registration or publish commands.
- `.claude/` is gitignored, so keep shared agent guidance in `AGENTS.md` or this file.
- The README project tree lists `src/cuda_backend.jl`, which does not exist; the CUDA code is in `ext/CUDABackendExt.jl`.
- Cold `Pkg.instantiate()` precompiles Plots, SymbolicRegression, and CUDA artifacts and took about 10 minutes here.
- Edit only what the task needs.
