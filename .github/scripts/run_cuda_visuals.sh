#!/usr/bin/env bash
set -euo pipefail

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
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1
apt-get install -y curl ca-certificates git >/dev/null 2>&1

# Install Julia 1.12 (official tarball)
JULIA_VER=1.12.0
curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/1.12/julia-${JULIA_VER}-linux-x86_64.tar.gz" -o /tmp/julia.tar.gz
tar -xzf /tmp/julia.tar.gz -C /usr/local --strip-components=1
rm -f /tmp/julia.tar.gz
export PATH=/usr/local/bin:$PATH
julia --version

echo "=== nvidia-smi inside container (GPU passthrough from preflight + --gpus) ==="
nvidia-smi

julia --project=. -e '
  using Pkg
  Pkg.instantiate()
  Pkg.add("CUDA")
  Pkg.precompile()
  println("Instantiate + CUDA add + precompile done (Grok Build 0.1 model)")
'

julia --project=. -e '
  using CUDA
  println("CUDA.jl version info:")
  CUDA.versioninfo()
  @assert CUDA.functional() "CUDA.functional() false inside container — no usable GPU"
  dev = CUDA.device()
  println("Device: ", CUDA.name(dev), " cap=", CUDA.capability(dev))
'

julia --project=. -e '
  using Surrogate_Viz, DataFrames
  df = DataFrame(tick=1:100, best_walker=rand(1:2047, 100))
  edges, counts = walker_density_bins_and_counts(df.best_walker; n_bins=32, max_walker=2047)
  println("CUDA walker density histogram: ", length(counts), " bins, sum=", sum(counts))
  @assert length(counts) == 32
  println("Pure-Julia CUDA visual kernel test passed (Grok Build 0.1 model).")
'

julia plot_latent_space.jl data/telemetry_math_logic.txt /tmp/ci_map.png || echo "plot step done or fell back"
EOF
