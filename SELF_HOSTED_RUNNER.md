# Self-Hosted Runner Setup

This document explains how to start, manage, and troubleshoot the local self-hosted GitHub Actions runner for `Surrogate_Viz.jl`.

## Quick Start

```bash
cd ~/actions-runner/Surrogate_Viz.jl-runner
./run-ephemeral.sh
```

## Runner Details

| Property | Value |
|----------|-------|
| **Machine** | ShipOfTheseus |
| **Path** | `~/actions-runner/Surrogate_Viz.jl-runner` |
| **Repository** | `https://github.com/rmems/Surrogate_Viz.jl` |
| **Labels** | `self-hosted, Linux, X64, gpu, sm120, julia-cuda, docker` |
| **Mode** | Ephemeral (one job per registration, auto-restarts) |

## How It Works

The runner uses **ephemeral mode** — each job gets a fresh registration:

1. Runner registers with GitHub
2. Picks up one job from the queue
3. Runs the job
4. Exits
5. `run-ephemeral.sh` automatically:
   - Generates a new registration token via `gh api`
   - Clears old credentials
   - Re-registers the runner
   - Starts listening for the next job

This ensures clean job isolation with no state pollution between runs.

## Manual Runner Start (Without Ephemeral Mode)

If you want to run the runner without auto-restart:

```bash
cd ~/actions-runner/Surrogate_Viz.jl-runner
./run.sh
```

This runs until you press `Ctrl+C`. The runner will handle multiple jobs without re-registering.

## Regenerating Runner Token

The registration token expires periodically. To regenerate:

```bash
# Via GitHub CLI
gh api --method POST repos/rmems/Surrogate_Viz.jl/actions/runners/registration-token --jq '.token'

# Or via web UI:
# https://github.com/rmems/Surrogate_Viz.jl/settings/actions/runners
```

## Reconfiguring the Runner

To change labels or other settings:

```bash
cd ~/actions-runner/Surrogate_Viz.jl-runner

# Remove current config
rm -f .runner .credentials .credentials_rsaparams .runner_migrated

# Reconfigure with new settings
./config.sh \
  --url https://github.com/rmems/Surrogate_Viz.jl \
  --token <NEW_TOKEN> \
  --labels self-hosted,Linux,X64,gpu,sm120,julia-cuda,docker \
  --ephemeral
```

## CI Workflow Labels

The workflows in `.github/workflows/julia.yml` require these labels:

```yaml
runs-on: [self-hosted, Linux, X64, gpu, sm120, julia-cuda, docker]
```

| Label | Purpose |
|-------|---------|
| `self-hosted` | Identifies as self-hosted runner |
| `Linux` | OS platform |
| `X64` | Architecture |
| `gpu` | Has GPU capability |
| `sm120` | NVIDIA SM 12.0 (RTX 5080) |
| `julia-cuda` | Julia + CUDA environment |
| `docker` | Docker available |

## Troubleshooting

### Runner not picking up jobs

1. Check if runner is running: `ps aux | grep Runner.Listener`
2. Check labels match workflow requirements: `gh api repos/rmems/Surrogate_Viz.jl/actions/runners --jq '.runners[] | {name: .name, status: .status, labels: [.labels[].name]}'`
3. Restart the runner: `./run-ephemeral.sh`

### "Session already exists" error

```bash
# Kill existing runner process
pkill -f "Runner.Listener"

# Wait 5 seconds
sleep 5

# Restart
./run-ephemeral.sh
```

### Registration token expired

```bash
# Generate new token
NEW_TOKEN=$(gh api --method POST repos/rmems/Surrogate_Viz.jl/actions/runners/registration-token --jq '.token')

# Clear old config
rm -f .runner .credentials .credentials_rsaparams

# Reconfigure
echo -e "\nShipOfTheseus\nY\n" | ./config.sh \
  --url https://github.com/rmems/Surrogate_Viz.jl \
  --token "$NEW_TOKEN" \
  --labels self-hosted,Linux,X64,gpu,sm120,julia-cuda,docker \
  --ephemeral
```

### CUDA tests not running

Ensure CUDA is installed in the test environment. The workflow includes:

```yaml
- name: Instantiate with CUDA
  run: julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.add("CUDA")'
```

## Checking Runner Status

```bash
# List all runners and their status
gh api repos/rmems/Surrogate_Viz.jl/actions/runners --jq '.runners[] | {name: .name, status: .status, labels: [.labels[].name]}'

# Check recent runs
gh run list --repo rmems/Surrogate_Viz.jl --limit 5

# Check specific run
gh run view <run_id> --repo rmems/Surrogate_Viz.jl
```

## Architecture

```
ShipOfTheseus (RTX 5080)
└── ~/actions-runner/Surrogate_Viz.jl-runner/
    ├── run-ephemeral.sh      # Auto-restart wrapper
    ├── run.sh                # Standard runner start
    ├── config.sh             # Runner configuration
    ├── .runner               # Runner identity
    ├── .credentials          # Authentication
    └── _work/                # Job workspace
```
