#!/bin/bash
# Entrypoint for Surrogate_Viz.jl Docker GPU runner
# Grok Build 0.1 model

set -e

RUNNER_NAME=${RUNNER_NAME:-"Surrogate-Viz-sm120-GPU-docker"}
GITHUB_URL=${GITHUB_URL:-"https://github.com/rmems/Surrogate_Viz.jl"}
RUNNER_LABELS=${RUNNER_LABELS:-"self-hosted,gpu,sm120,julia-cuda"}

echo "=== Surrogate_Viz.jl GPU Runner (Grok Build 0.1 model) ==="
echo "Name: $RUNNER_NAME"
echo "URL: $GITHUB_URL"
echo "Labels: $RUNNER_LABELS"
echo "CUDA visible? (will be checked inside jobs via nvidia-smi)"
nvidia-smi --query-gpu=name,compute_cap --format=csv || echo "nvidia-smi not available yet (host --gpus required)"

# If no .runner config exists, configure (requires GITHUB_TOKEN / registration token)
if [ ! -f .runner ]; then
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "ERROR: GITHUB_TOKEN (PAT or registration token) is required for first-time config."
        echo "See runner.env.example"
        exit 1
    fi
    echo "Configuring runner..."
    ./config.sh \
        --url "$GITHUB_URL" \
        --token "$GITHUB_TOKEN" \
        --name "$RUNNER_NAME" \
        --labels "$RUNNER_LABELS" \
        --unattended \
        --replace \
        --work _work
fi

echo "Starting runner..."
exec ./run.sh
