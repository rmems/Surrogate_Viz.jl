# Docker GPU self-hosted GitHub Actions runner for Surrogate_Viz.jl CUDA jobs
# Supports sm_120 (Blackwell / RTX 50-series) via recent NVIDIA CUDA base.
# Grok Build 0.1 model: created to reliably run the cuda-visuals job on local host runner
# with proper GPU passthrough, isolation, and Julia 1.12 + CUDA.jl environment.

FROM nvidia/cuda:12.8.1-devel-ubuntu22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies for runner + Julia + common build tools
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    wget \
    build-essential \
    ca-certificates \
    libicu70 \
    libssl3 \
    zlib1g \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub Actions Runner (version matching previous manual setup)
ARG RUNNER_VERSION=2.334.0
WORKDIR /home/runner
RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && ./bin/installdependencies.sh

# Install Julia 1.12 (required by the workflow)
RUN curl -fsSL https://install.julialang.org | sh -s -- --yes --default-channel 1.12
ENV PATH="/root/.juliaup/bin:/opt/julia-1.12.0/bin:${PATH}"
# Verify
RUN julia --version

# Create runner user (best practice, avoids running as root)
RUN useradd -m -s /bin/bash runner \
    && chown -R runner:runner /home/runner

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
WORKDIR /home/runner

# Default entrypoint handles registration + run
ENTRYPOINT ["/entrypoint.sh"]
