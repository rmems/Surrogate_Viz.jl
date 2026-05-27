# Validation Commands

This file collects exact smoke-test commands for CI, contributors, and PR verification.

## Bundle Ingestion Smoke Tests

All commands assume the working directory is the repo root (`Surrogate_Viz.jl/`).

### 1. Install dependencies

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### 2. Validate a single fixture bundle

```bash
julia --project=. scripts/validate_saaq_bundle.jl test/fixtures/bundles/successful_synthetic/
# Expected: exit code 0, prints run details

julia --project=. scripts/validate_saaq_bundle.jl test/fixtures/bundles/skipped_run/
# Expected: exit code 0

julia --project=. scripts/validate_saaq_bundle.jl test/fixtures/bundles/failed_run/
# Expected: exit code 0 (failed bundles are valid bundles, just with failed status)

julia --project=. scripts/validate_saaq_bundle.jl test/fixtures/bundles/nonexistent/
# Expected: exit code 1, error message
```

### 3. Ingest all fixture bundles → normalized CSVs

```bash
julia --project=. scripts/ingest_saaq_bundles.jl test/fixtures/bundles/ /tmp/saaq_normalized/
# Expected: writes runs_table.csv, metrics_table.csv, warnings_table.csv under /tmp/saaq_normalized/
# 5 runs ingested (successful_synthetic, skipped_run, failed_run, missing_optional, unknown_extras)
```

### 4. Build dashboard from normalized fixtures

```bash
julia --project=. scripts/build_saaq_dashboard.jl /tmp/saaq_normalized/ /tmp/saaq_reports/
# Expected: writes dashboard.html, summary.md, runs_table.csv, metrics_table.csv,
#           warnings_table.csv under /tmp/saaq_reports/<yyyy-mm-dd>/
```

### 5. Run full test suite

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
# Expected: all tests pass including new SaaqBundleLoader and SaaqNormalizer tests
```

## Fixture Coverage

| Fixture | Run Status | Coverage |
|---|---|---|
| `successful_synthetic/` | `real` | Complete manifest + summary, heartbeat on |
| `skipped_run/` | `skipped` | Missing metrics (ticks_completed=0) |
| `failed_run/` | `failed` | error field set, validation_status=failed |
| `missing_optional/` | `real` | Many optional manifest fields absent |
| `unknown_extras/` | `real` | Unknown extra fields in manifest + summary.metrics |

## What Is Real vs Synthetic

- **Real runs**: runs where `validation_status = "completed"` and `error = null`
- **Synthetic runs**: fixture/test runs marked `run_status = synthetic` in the manifest
  (currently `successful_synthetic` is marked real since it has completed status)
- **Skipped runs**: `validation_status = "skipped"` — incomplete runs, no metrics
- **Failed runs**: `validation_status = "failed"` or `error !== null` — runs that errored

## Notes

- `warnings.jsonl` is defined in the corinth-canal schema but not currently emitted.
  The warning table will always be empty until corinth-canal starts writing that file.
- `artifacts.json` is defined in the schema but not emitted. Artifact references
  are not yet supported in this ingestion layer.
- Unknown manifest and metrics fields are preserved in the `extra` dict on each struct
  and exposed as `extra_<field>` columns in the runs/metrics tables.