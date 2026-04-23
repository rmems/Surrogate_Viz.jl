# Surrogate_Viz.jl

Julia-based SymbolicRegression + visualization workbench for
[corinth-canal](../corinth-canal) SAAQ telemetry. Consumes dual-SAAQ CSVs
and tick telemetry emitted by the Rust simulator and produces SR.jl
hall-of-fame discoveries plus heartbeat validation dashboards.

## MoE Target Models

Current experimentation targets the following five mixture-of-experts
instructor models:

1. `DeepSeek-Coder-V2-Lite-Instruct-Q6_K_L.gguf`
2. `gemma-4-26B-A4B-it-UD-IQ4_NL.gguf`
3. `L3.2-8X3B-MOE-Dark-Champion-Inst-18.4B-uncen-ablit_D_AU-q5_k_m.gguf`
4. `olmoe-1b-7b` (default)
5. `qwen3-moe-i1-GGUF IQ3_M.gguf`

Select the active model at runtime with the `MODEL` env var, e.g.
`MODEL="qwen3-moe-i1-GGUF IQ3_M.gguf" julia plot_saaq15_validation.jl`.

## Project Structure

```
Surrogate_Viz.jl/
├── SAAQ_discovery.jl         # SR.jl over raw RE4 telemetry
├── SAAQ_latent_discovery.jl  # SR.jl over 508-neuron latent telemetry
├── plot_saaq15_validation.jl # Heartbeat/SAAQ 1.5 validation dashboard
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

## Importing corinth-canal runs

`corinth-canal` remains the producer of SAAQ artifacts under its own
`artifacts/` tree. `Surrogate_Viz.jl` only imports selected runs from
that repo and builds local comparison plots/reports from the imported
files.

The selected baseline runs are listed in `data/selected_runs.toml`.
Import them into deterministic local paths under
`data/corinth_runs/<model>/<telemetry_source>/<heartbeat>/<run_id>/`
with:

```bash
julia import_corinth_runs.jl
```

Imports prefer symlinks for the three source files
(`latent_telemetry.csv`, `tick_telemetry.txt`, `summary.json`) and fall
back to copies if symlinks are unavailable. Re-import in overwrite mode
with `FORCE_IMPORT=true julia import_corinth_runs.jl`.

After importing, compare the blessed OLMoE RE4 SAAQ 1.5 heartbeat pair
for repeat `0` with:

```bash
julia compare_saaq15_baseline_pair.jl
```

This writes a compact PNG plus markdown summary under
`outputs/olmoe-1b-7b/dashboards/`.
