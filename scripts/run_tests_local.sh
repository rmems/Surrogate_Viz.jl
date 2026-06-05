#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

julia_bin="${JULIA_BIN:-julia}"
direct_julia="${HOME}/.julia/juliaup/julia-1.12.6+0.x64.linux.gnu/bin/julia"

if [[ "${julia_bin}" == "julia" ]] && ! "${julia_bin}" --version >/dev/null 2>&1 && [[ -x "${direct_julia}" ]]; then
    julia_bin="${direct_julia}"
fi

depot_root="${JULIA_WRITABLE_DEPOT:-${repo_root}/.julia_depot}"
mkdir -p "${depot_root}"

export JULIA_DEPOT_PATH="${depot_root}:${HOME}/.julia"

"${julia_bin}" --project="${repo_root}" -e 'using Pkg; Pkg.instantiate()'
"${julia_bin}" --project="${repo_root}" -e 'using Pkg; Pkg.test()'
