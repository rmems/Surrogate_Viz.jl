# Surrogate_Viz.jl

Julia-based SymbolicRegression + visualization workbench for
[corinth-canal](../corinth-canal) SAAQ telemetry. Consumes dual-SAAQ CSVs
and tick telemetry emitted by the Rust simulator and produces SR.jl
hall-of-fame discoveries plus paired-run validation dashboards.

> **Status:** corinth-canal is not yet ready. All SAAQ bundles currently
> come from synthetic fixtures under `test/fixtures/bundles/`. Real
> corinth-canal integration will be documented once the pipeline is live.

## Quick Start

```bash
# Install dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run the full test suite
julia --project=. -e 'using Pkg; Pkg.test()'

# Local fallback if juliaup or depot writeability is constrained
./scripts/run_tests_local.sh

# Validate a single SAAQ bundle
julia --project=. scripts/validate_saaq_bundle.jl test/fixtures/bundles/successful_synthetic/

# Ingest SAAQ fixtures into normalized CSV tables
julia --project=. scripts/ingest_saaq_bundles.jl test/fixtures/bundles/ /tmp/saaq_normalized/

# Validate a single grok-ozempic bundle
julia --project=. scripts/validate_grok_ozempic_bundle.jl test/fixtures/grok_ozempic/pass/

# Ingest grok-ozempic fixtures into normalized CSV tables
julia --project=. scripts/ingest_grok_ozempic_bundles.jl test/fixtures/grok_ozempic/ /tmp/grok_normalized/
```

## MoE Target Models

Current experimentation targets nine mixture-of-experts instructor
models, organized by corinth-canal lineup slug:

| # | corinth-canal slug | GGUF / local name |
|---|-------------------|-------------------|
| 1 | `olmoe_baseline` | `olmoe-1b-7b` (default) |
| 2 | `qwen3_moe_i1_iq3_m` | `qwen3-moe-i1-GGUF IQ3_M.gguf` |
| 3 | `gemma4_26b_a4b_iq4_nl` | `gemma-4-26B-A4B-it-UD-IQ4_NL.gguf` |
| 4 | `deepseek_coder_v2_lite_q6_k_l` | `DeepSeek-Coder-V2-Lite-Instruct-Q6_K_L.gguf` |
| 5 | `llama_3_2_dark_champion_q5_k_m` | `L3.2-8X3B-MOE-Dark-Champion-Inst-18.4B-uncen-ablit_D_AU-q5_k_m.gguf` |
| 6 | `zaya1_8b_q8_0` | Zaya 1 (Abiray/ZAYA1-8B-GGUF) |
| 7 | `glm46v_flash_q8_0` | GLM-4.6V-Flash |
| 8 | `kimi_vl_a3b_q6_k` | Kimi-VL-A3B-Instruct |
| 9 | `marco_nano_base_q8_0` | Marco-Nano-Base |

Models 6–9 were onboarded in [corinth-canal#68](https://github.com/rmems/corinth-canal/pull/68).

Select the active model at runtime with the `MODEL` env var, e.g.
`MODEL="qwen3-moe-i1-GGUF IQ3_M.gguf" julia plot_saaq1_5_validation.jl`.

> **Note on terminology:** The simulator emits a `condition_signal` column and
> uses `baseline` / `treatment` as condition labels in the run manifest.
> Plot titles and report headers use neutral terms (*control-off* /
> *control-on*, *paired-run*).

## Project Structure

```
Surrogate_Viz.jl/
├── src/
│   ├── Surrogate_Viz.jl          # Main module: includes, exports, paired-run logic
│   ├── backend.jl                # ComputeBackend abstraction (CPUBackend / CUDABackend)
│   ├── kernels.jl                # CPU dispatch targets for compute kernels
│   ├── grok_ozempic.jl           # Grok-ozempic bundle structs, loader, validator
│   └── normalizers/
│       ├── SaaqNormalizer.jl     # SAAQ bundle → DataFrames
│       └── GrokOzempicNormalizer.jl  # Grok-ozempic bundle → DataFrames
├── ext/
│   └── CUDABackendExt.jl         # CUDA package extension (GPU acceleration)
├── scripts/
│   ├── validate_saaq_bundle.jl   # Validate a single SAAQ bundle
│   ├── ingest_saaq_bundles.jl    # Walk directory → normalized CSVs
│   ├── build_saaq_dashboard.jl   # Build static HTML dashboard
│   ├── validate_grok_ozempic_bundle.jl  # Validate a single grok-ozempic bundle
│   └── ingest_grok_ozempic_bundles.jl   # Walk directory → normalized CSVs
├── test/
│   ├── runtests.jl               # Full test suite (SAAQ + CUDA + grok-ozempic)
│   └── fixtures/
│       ├── bundles/              # SAAQ synthetic fixture bundles
│       └── grok_ozempic/         # Grok-ozempic synthetic fixture bundles
├── docs/
│   └── validation.md             # Smoke-test commands for CI
├── data/                         # (gitignored) model checkpoints + imported runs
│   ├── olmoe-1b-7b/              # .gitkeep (GGUF, default)
│   ├── qwen3-moe-i1-GGUF IQ3_M.gguf/   # .gitkeep (GGUF)
│   ├── gemma-4-26B-A4B-it-UD-IQ4_NL.gguf/   # .gitkeep (GGUF)
│   ├── DeepSeek-Coder-V2-Lite-Instruct-Q6_K_L.gguf/   # .gitkeep (GGUF)
│   ├── L3.2-8X3B-MOE-Dark-Champion-Inst-18.4B-uncen-ablit_D_AU-q5_k_m.gguf/   # .gitkeep (GGUF)
│   ├── zaya1_8b_q8_0/            # .gitkeep (GGUF)
│   ├── glm46v_flash_q8_0/        # .gitkeep (GGUF)
│   ├── kimi_vl_a3b_q6_k/         # .gitkeep (GGUF)
│   └── marco_nano_base_q8_0/     # .gitkeep (GGUF)
├── outputs/                      # (gitignored) generated dashboards + SR results
│   ├── olmoe-1b-7b/
│   │   ├── dashboards/           # .gitkeep
│   │   └── sr_results/           # .gitkeep
│   ├── qwen3-moe-i1-GGUF IQ3_M.gguf/
│   │   ├── dashboards/
│   │   └── sr_results/
│   ├── gemma-4-26B-A4B-it-UD-IQ4_NL.gguf/
│   │   ├── dashboards/
│   │   └── sr_results/
│   ├── DeepSeek-Coder-V2-Lite-Instruct-Q6_K_L.gguf/
│   │   ├── dashboards/
│   │   └── sr_results/
│   ├── L3.2-8X3B-MOE-Dark-Champion-Inst-18.4B-uncen-ablit_D_AU-q5_k_m.gguf/
│   │   ├── dashboards/
│   │   └── sr_results/
│   ├── zaya1_8b_q8_0/
│   │   ├── dashboards/
│   │   └── sr_results/
│   ├── glm46v_flash_q8_0/
│   │   ├── dashboards/
│   │   └── sr_results/
│   ├── kimi_vl_a3b_q6_k/
│   │   ├── dashboards/
│   │   └── sr_results/
│   └── marco_nano_base_q8_0/
│       ├── dashboards/
│       └── sr_results/
├── SAAQ_discovery.jl             # SR.jl over raw RE4 telemetry
├── SAAQ_latent_discovery.jl      # SR.jl over 508-neuron latent telemetry
├── plot_saaq1_5_validation.jl    # SAAQ 1.5 paired-run validation dashboard
├── plot_latent_space.jl          # Latent space exploration plot
├── compare_full_lineup_saaq1_5.jl
├── compare_saaq1_5_baseline_pair.jl
├── import_corinth_runs.jl
└── Project.toml
```

## Compute Backend

`Surrogate_Viz` supports both CPU and (optional) GPU acceleration via a
compute backend abstraction:

| Backend | Description |
|---|---|
| `CPUBackend()` | Default. Pure-Julia computation on the CPU. |
| `CUDABackend()` | GPU acceleration via CUDA.jl. Falls back to CPU if CUDA is unavailable. |

### CUDA Setup

CUDA is a **weak dependency** — it's never installed unless you explicitly
add it. If you have a CUDA-capable GPU:

```julia
using Pkg
Pkg.add("CUDA")
using CUDA  # triggers the CUDABackendExt package extension
```

Then pass `backend=CUDABackend()` to `summarise_run`, `pairwise_summary`,
or `compute_delta_per_tick`. If CUDA is not functional, the CUDA backend
automatically falls back to CPU with a warning.

The extension uses:
- On-device GPU reductions (`mean(gpu)`, `maximum(gpu)`) to avoid
  full Array transfers for scalar results
- `CUDA.@allowscalar` for scalar CuArray indexing
- Instance-based dispatch (`::CUDABackend`) for correct Julia method resolution

## SAAQ Bundle Ingestion

`Surrogate_Viz.jl` can ingest corinth-canal run bundles directly from
`artifacts/<campaign>/<model>/<telemetry_source>/<condition>/<run_id>/`
directories without needing the old `selected_runs.toml` workflow.

Each bundle contains:

| File | Purpose |
|---|---|
| `run_manifest.json` | Run identity, model, SAAQ rule, telemetry source, router policy |
| `summary.json` | Metrics: ticks completed, latent rows, timing, repeat determinism |

### Validate a single bundle

```bash
julia --project=. scripts/validate_saaq_bundle.jl /path/to/run_dir
```

Exit code 0 means the bundle is valid. Exit 1 means it has errors.

### Ingest a directory tree into normalized CSV tables

```bash
julia --project=. scripts/ingest_saaq_bundles.jl <input_dir> <output_dir>
```

Walks `<input_dir>` recursively, finds all `run_manifest.json` files,
loads each bundle, and writes three CSV files to `<output_dir>/`:

- `runs_table.csv` — one row per run (identity, status, model, SAAQ rule, telemetry)
- `metrics_table.csv` — one row per metric (run_id, name, value, category)
- `warnings_table.csv` — one row per warning (run_id, category, message, severity)

### Build a static HTML dashboard from normalized tables

```bash
julia --project=. scripts/build_saaq_dashboard.jl <normalized_dir> <report_dir>
```

Reads the CSV tables from `<normalized_dir>` and writes:

```
<report_dir>/<yyyy-mm-dd>/
  dashboard.html    # compact HTML dashboard with tables
  summary.md        # markdown summary with run overview table
  runs_table.csv    # (copied)
  metrics_table.csv # (copied)
  warnings_table.csv # (copied)
```

## Grok-Ozempic Bundle Ingestion

`Surrogate_Viz.jl` can ingest grok-ozempic validation report bundles.
Each bundle is a directory containing a `validation.report.json` file.

### Report Schema

The `GrokOzempicReport` struct captures:

| Field | Type | Description |
|---|---|---|
| `status` | `String` | `"PASS"` or `"FAIL"` |
| `source_tensor_count` | `Int64` | Number of source tensors |
| `artifact_tensor_count` | `Int64` | Number of artifact tensors |
| `router_count` | `Int64` | Router count |
| `protected_router_violations` | `Int64` | Protected router violations |
| `protected_norm_violations` | `Int64` | Protected norm violations |
| `expert_association_count` | `Int64` | Expert association count |
| `unknown_unresolved_warning_count` | `Int64` | Unresolved warnings |
| `checksum_coverage` | `String` | Checksum coverage description |
| `source_total_bytes` | `Int64` | Total source bytes |
| `artifact_total_bytes` | `Int64` | Total artifact bytes |
| `byte_accounting_result` | `String` | `"match"` or `"mismatch"` |
| `failures` | `Vector{GrokOzempicFailure}` | Failure entries |
| `warnings` | `Vector{GrokOzempicWarning}` | Warning entries |
| `extra` | `Dict{String,Any}` | Unknown fields preserved as `extra_<field>` |

### Validate a single bundle

```bash
julia --project=. scripts/validate_grok_ozempic_bundle.jl /path/to/bundle_dir
```

### Ingest a directory tree into normalized CSV tables

```bash
julia --project=. scripts/ingest_grok_ozempic_bundles.jl <input_dir> <output_dir>
```

Writes three CSV files to `<output_dir>/`:

- `runs_table.csv` — one row per bundle (status, tensor counts, byte accounting)
- `metrics_table.csv` — one row per metric (bundle_path, name, value, category)
- `issues_table.csv` — one row per failure/warning (bundle_path, issue_category, tensor, message, severity)

### Programmatic API

```julia
using Surrogate_Viz

# Load a single bundle
bundle = load_grok_ozempic_bundle("path/to/bundle_dir")

# Validate (non-throwing)
is_valid, errors = validate_grok_ozempic_bundle("path/to/bundle_dir")

# Normalize to DataFrames
runs_df, metrics_df, issues_df = normalize_grok_ozempic_to_tables(bundle)

# Batch: normalize entire directory tree
runs_df, metrics_df, issues_df = normalize_grok_ozempic_dir("path/to/bundles/")
```

## Repo Separation: Surrogate_Viz.jl vs corinth-canal

| Concern                                  | Owner              |
| ---------------------------------------- | ------------------ |
| SNN simulator, SAAQ rules, CSV emission  | `corinth-canal`    |
| Simulator unit/integration tests         | `corinth-canal`    |
| Dual-SAAQ + telemetry schema             | `corinth-canal`    |
| SymbolicRegression.jl driver scripts     | `Surrogate_Viz.jl` |
| Plots / dashboards / exploratory notes   | `Surrogate_Viz.jl` |
| `hall_of_fame.csv` + PNG artifacts       | `Surrogate_Viz.jl/outputs/` |

**One-way data flow:** simulator outputs land under
`data/<model>/` in this repo; generated artifacts live under
`outputs/<model>/{dashboards,sr_results}/`. Never edit simulator code or
commit raw simulator CSVs from this side.

## Full Lineup Comparison

`compare_full_lineup_saaq1_5.jl` reads `data/selected_runs.toml` for entries
tagged `campaign = "full_lineup"`, repeat-0, with telemetry source
`csv_re4_path_tracing_telemetry` and rule `SaaqV1_5SqrtRate`. For each
available model slug (see model table above) it pairs the control-off vs
control-on runs, writes one PNG per model and a single combined markdown
report under `outputs/full_lineup/`. Models without complete paired runs
are gracefully skipped with a warning.

```
julia --project=. import_corinth_runs.jl
julia --project=. compare_full_lineup_saaq1_5.jl
# outputs/full_lineup/full_lineup_saaq1_5_comparison.md
# outputs/full_lineup/<model_slug>.png  (one per model)
```

## Importing corinth-canal runs

`corinth-canal` remains the producer of SAAQ artifacts under its own
`artifacts/` tree. `Surrogate_Viz.jl` only imports selected runs from
that repo and builds local comparison plots/reports from the imported
files.

The selected baseline runs are listed in `data/selected_runs.toml`.
Import them into deterministic local paths under
`data/corinth_runs/<model>/<telemetry_source>/<condition>/<run_id>/`
with:

```bash
julia import_corinth_runs.jl
```

Imports prefer symlinks for the three source files
(`latent_telemetry.csv`, `tick_telemetry.txt`, `summary.json`) and fall
back to copies if symlinks are unavailable. Re-import in overwrite mode
with `FORCE_IMPORT=true julia import_corinth_runs.jl`.

After importing, compare the blessed OLMoE RE4 SAAQ 1.5 paired-run
baseline for repeat `0` with:

```bash
julia compare_saaq1_5_baseline_pair.jl
```

This writes a compact PNG plus markdown summary under
`outputs/olmoe-1b-7b/dashboards/`.

## Tests

Run the test suite from the repo root:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using Pkg; Pkg.test()'
```

If `julia` is launched through `juliaup` and fails before startup, or your
default depot is not writable, use the repo-supported local wrapper instead:

```bash
./scripts/run_tests_local.sh
```

Override the Julia binary with `JULIA_BIN=/path/to/julia` if your local 1.12
binary lives somewhere else.

Tests cover the `Surrogate_Viz` module's shared utilities — import paths,
telemetry column detection, paired-run comparison mechanics, bundle
loading, normalization, compute backend abstraction, and number
formatting — using synthetic neutral-paired-run fixtures. No simulator
data or condition-specific behavior is required.

### Test coverage

| Test set | What it covers |
|---|---|
| Module exports | All public names are exported |
| `fmt`, `to_float64_vec`, `to_int_ms` | Utility functions |
| `detect_delta_column`, `maybe_entropy_column` | Column detection |
| `summarise_run`, `pairwise_summary` | Paired-run mechanics (CPU backend) |
| Path validation | Traversal rejection, absolute-path rejection |
| `SaaqBundleLoader` | Bundle loading, validation, missing/extra fields |
| `SaaqNormalizer` | Normalization to DataFrames, directory ingestion |
| `ComputeBackend` | CPUBackend / CUDABackend types, `has_cuda()` |
| `compute_delta_per_tick` | CPU backend delta computation |
| CUDA path (if available) | GPU ↔ CPU parity checks |
| `GrokOzempic` | Bundle loading, validation, all 4 fixture types |
| `GrokOzempicNormalizer` | Normalization, directory ingestion |
