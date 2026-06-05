#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

julia_bin="${JULIA_BIN:-julia}"

# Try juliaup first (most robust), then fall back to PATH julia
if command -v juliaup >/dev/null 2>&1; then
    julia_bin="$(juliaup default)"
fi

if [[ "${julia_bin}" == "julia" ]] && ! "${julia_bin}" --version >/dev/null 2>&1; then
    # final fallback: any julia on PATH
    julia_bin="julia"
fi

depot_root="${JULIA_WRITABLE_DEPOT:-${repo_root}/.julia_depot}"
mkdir -p "${depot_root}"

export JULIA_DEPOT_PATH="${depot_root}:${HOME}/.julia"

"${julia_bin}" --project="${repo_root}" -e 'using Pkg; Pkg.instantiate()'
"${julia_bin}" --project="${repo_root}" -e 'using Pkg; Pkg.test()'
