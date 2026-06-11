# Dockerfile
# Grok Build 0.1 model: root Dockerfile for reproducible GPU workflows with
# NVIDIA CUDA + Julia 1.12. This follows the (read-only) corinth-canal
# representation of Docker + GPU on local hosted runners:
# - nvidia/cuda devel base (pinned version)
# - The actions-runner (bare, from actions-runner tarball/config.sh) on the
#   host executes workflow steps that can `docker build` or `docker run` this.
# - Separate ephemeral usage in .github/workflows/julia.yml cuda-visuals
#   (docker run upstream nvidia/cuda + install Julia inside) keeps validation
#   fast and matches corinth-canal's gpu-tests.yml "Compile ... in pinned"
#   pattern exactly.
#
# Labels and security: self-hosted jobs using this still require the
# if: head.repo.full_name guard (see julia.yml).
#
# Build (on a machine with docker + nvidia-container-toolkit):
#   docker build --build-arg CUDA_VERSION=13.2.0 -t surrogate-viz:gpu .
# Run with GPU (for CUDA.jl execution):
#   docker run --rm --gpus all -v "$PWD:/app" -w /app surrogate-viz:gpu \
#     julia --project=. -e 'using Surrogate_Viz, DataFrames; ...'
#
# CUDA_VERSION chosen for sm_120 (RTX 50-series) compatibility.
# Julia installed via official tarball for non-interactive reliability.

ARG CUDA_VERSION=13.2.0

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04

LABEL org.opencontainers.image.source="https://github.com/rmems/Surrogate_Viz.jl"
LABEL description="Surrogate_Viz.jl CUDA + Julia 1.12 env for sm_120 GPU CI (Grok Build 0.1 model)"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# Install exact Julia 1.12 (tarball; avoids juliaup prompts in CI/containers)
RUN set -e; \
    JULIA_VER=1.12.0; \
    curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/1.12/julia-${JULIA_VER}-linux-x86_64.tar.gz" -o /tmp/julia.tar.gz; \
    tar -xzf /tmp/julia.tar.gz -C /usr/local --strip-components=1; \
    rm /tmp/julia.tar.gz; \
    /usr/local/bin/julia --version

ENV PATH="/usr/local/bin:${PATH}"

# Quick sanity (nvidia-smi will only show devices if --gpus passed at `docker run`)
RUN julia --version && (command -v nvidia-smi >/dev/null && nvidia-smi --version || echo "nvidia-smi available only with GPU passthrough")

WORKDIR /app

# Layer cache: manifests first
COPY Project.toml Manifest.toml* ./

# Instantiate dependencies during build; precompilation is deferred to runtime/CI.
RUN julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Full source
COPY . .

# Default: run the test suite (CPU paths always work; CUDA when GPU mounted)
CMD ["julia", "--project=.", "-e", "using Pkg; Pkg.test()"]
