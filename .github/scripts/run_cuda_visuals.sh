#!/usr/bin/env bash
set -euo pipefail
# Grok Build 0.1 model: extracted from the cuda-visuals step so the long
# docker + Julia + CUDA work is easy to read and to run manually for repro.
# See the big comment block in the gpu-preflight step of julia.yml for the
# one-time host setup (usermod + nvidia-ctk) that is almost always the real
# cause when you see "docker failed on actions-runner terminal".

DOCKER_BIN="$(command -v docker || true)"
if [ -z "$DOCKER_BIN" ] && [ -x /usr/bin/docker ]; then
  DOCKER_BIN=/usr/bin/docker
fi
[ -n "$DOCKER_BIN" ]
"$DOCKER_BIN" --version

"$DOCKER_BIN" run --rm --gpus all \
  -v "$PWD:/app" \
  -w /app \
  nvidia/cuda:13.2.0-devel-ubuntu22.04 \
  bash -s <<'EOF'
set -euo pipefail
set -x   # Extra debug output for the CI logs (Grok Build 0.1 model)
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1
apt-get install -y curl ca-certificates git xvfb >/dev/null 2>&1 || true

# Install Julia 1.12 (official tarball)
JULIA_VER=1.12.0
curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/1.12/julia-${JULIA_VER}-linux-x86_64.tar.gz" -o /tmp/julia.tar.gz
tar -xzf /tmp/julia.tar.gz -C /usr/local --strip-components=1
rm -f /tmp/julia.tar.gz
export PATH=/usr/local/bin:$PATH
julia --version

echo "=== nvidia-smi inside container (GPU passthrough from preflight + --gpus) ==="
nvidia-smi || echo "WARNING: nvidia-smi exited non-zero inside the container (GPU passthrough may be incomplete or driver mismatch). Continuing for diagnostics..."

# Key fix: CUDA is weakdep + CUDABackendExt. Must add explicitly for the test env.
julia --project=. -e '
  using Pkg
  Pkg.instantiate()
  Pkg.add("CUDA")
  Pkg.precompile()
  println("Instantiate + CUDA add + precompile done (Grok Build 0.1 model)")
'

# Verify + assert functional (catches driver/runtime/CUDA.jl issues early)
julia --project=. -e '
  using CUDA
  println("CUDA.jl version info:")
  CUDA.versioninfo()
  @assert CUDA.functional() "CUDA.functional() false inside container — no usable GPU (check nvidia-smi output above, driver versions, and that the container really got --gpus all)"
  dev = CUDA.device()
  println("Device: ", CUDA.name(dev), " cap=", CUDA.capability(dev))
'

# The kernels under test (will now take the CUDA path)
julia --project=. -e '
  using Surrogate_Viz, DataFrames
  # Grok Build 0.1 model: synthetic only (no og data per request)
  df = DataFrame(tick=1:100, best_walker=rand(1:2047, 100))
  edges, counts = walker_density_bins_and_counts(df.best_walker; n_bins=32, max_walker=2047)
  println("CUDA walker density histogram: ", length(counts), " bins, sum=", sum(counts))
  @assert length(counts) == 32
  println("Pure-Julia CUDA visual kernel test passed (Grok Build 0.1 model).")
'

# Optional plot (guarded main(), telemetry_math_logic.txt, no og).
# Headless container: xvfb-run (installed above) or env vars so Plots doesn't
# try to open a real display and exit non-zero.
export GKSwstype=100
export MPLBACKEND=Agg
xvfb-run -a julia plot_latent_space.jl data/telemetry_math_logic.txt /tmp/ci_map.png \
  || echo "plot step done or fell back (xvfb or display not critical for CI)"
EOF
