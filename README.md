# Surrogate_Viz.jl

Julia-based SymbolicRegression + visualization workbench for
[corinth-canal](../corinth-canal) SAAQ telemetry. Consumes dual-SAAQ CSVs
and tick telemetry emitted by the Rust simulator and produces SR.jl
hall-of-fame discoveries plus paired-run validation dashboards.

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
├── SAAQ_discovery.jl         # SR.jl over raw RE4 telemetry
├── SAAQ_latent_discovery.jl  # SR.jl over 508-neuron latent telemetry
├── plot_saaq1_5_validation.jl # SAAQ 1.5 paired-run validation dashboard
├── plot_latent_space.jl      # Latent space exploration plot
├── data/                     # (gitignored, dirs kept via .gitkeep)
│   ├── DeepSeek-Coder-V2-Lite-Instruct-Q6_K_L.gguf/
│   ├── gemma-4-26B-A4B-it-UD-IQ4_NL.gguf/
│   ├── L3.2-8X3B-MOE-Dark-Champion-Inst-18.4B-uncen-ablit_D_AU-q5_k_m.gguf/
│   ├── olmoe-1b-7b/
│   └── qwen3-moe-i1-GGUF IQ3_M.gguf/
├── outputs/                  # (gitignored, dirs kept via .gitkeep)
│   ├── DeepSeek-Coder-V2-Lite-Instruct-Q6_K_L.gguf/
│   │   ├── dashboards/       # timestamped validation PNGs
│   │   └── sr_results/       # SR.jl hall_of_fame CSVs
│   ├── gemma-4-26B-A4B-it-UD-IQ4_NL.gguf/
│   ├── L3.2-8X3B-MOE-Dark-Champion-Inst-18.4B-uncen-ablit_D_AU-q5_k_m.gguf/
│   ├── olmoe-1b-7b/
│   └── qwen3-moe-i1-GGUF IQ3_M.gguf/
└── README.md
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

## SAAQ Bundle Ingestion (corinth-canal)

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

## Tests

Run the test suite from the repo root:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using Pkg; Pkg.test()'
```

Tests cover the `SurrogateViz` module's shared utilities — import paths,
telemetry column detection, paired-run comparison mechanics, bundle
loading, normalization, and number formatting — using synthetic
neutral-paired-run fixtures. No simulator data or condition-specific
behavior is required.
