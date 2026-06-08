using Statistics

function compute_pairwise_deltas(
    off_col::AbstractVector,
    on_col::AbstractVector,
    ::CPUBackend
)
    deltas = on_col .- off_col
    return (
        mean_delta = Statistics.mean(deltas),
        max_abs_delta = maximum(abs.(deltas)),
        final_delta = last(deltas),
    )
end

function compute_run_stats(
    delta_values::AbstractVector,
    entropy_values::Union{Nothing,AbstractVector},
    ::CPUBackend
)
    mean_delta = Statistics.mean(delta_values)
    max_delta = maximum(delta_values)
    final_delta = last(delta_values)

    if entropy_values !== nothing && !isempty(entropy_values)
        mean_entropy = Statistics.mean(entropy_values)
        final_entropy = last(entropy_values)
    else
        mean_entropy = missing
        final_entropy = missing
    end

    return (;
        mean_delta,
        max_delta,
        final_delta,
        mean_entropy,
        final_entropy,
    )
end

function compute_delta_per_tick(
    features::AbstractMatrix,
    ::CPUBackend
)
    return diff(features, dims=1)
end

function compute_delta_per_tick(
    timestamps::AbstractVector,
    features::AbstractMatrix,
    ::CPUBackend
)
    deltas = diff(features, dims=1)
    t_out = timestamps[2:end]
    return t_out, deltas
end

# -----------------------------------------------------------------------------
# Pure Julia CUDA visual kernels (Grok Build 0.1 model)
#
# These are implemented in ext/CUDABackendExt.jl so that the core package
# (src/*.jl) has no top-level references to CUDA symbols.
# This keeps the Julia Language Server (LSP) happy when it analyzes the
# main module without the CUDA package active in its environment.
#
# The functions are attached to the module at runtime when the CUDA
# extension loads. See ext/CUDABackendExt.jl for the real @cuda impl.
#
# For the standalone plot script and callers, we provide a fallback
# that works without CUDA, and the real version is used automatically
# when the extension is present (via the try/getproperty pattern in
# callers like plot_latent_space.jl).
# -----------------------------------------------------------------------------

# Plain-Julia fallback (always available, no CUDA symbols here).
function _plain_walker_histogram(best_walkers::AbstractVector{Int}, n_bins::Int, max_walker::Int)
    hist = zeros(Int, n_bins)
    bin_size = (max_walker + 1) / n_bins
    for w in best_walkers
        b = clamp(floor(Int, w / bin_size), 0, n_bins - 1) + 1
        hist[b] += 1
    end
    return hist
end

function walker_density_bins_and_counts(
    best_walkers::AbstractVector{Int};
    n_bins::Int = 32,
    max_walker::Int = 2047
)
    # Prefer the CUDA version only when the package extension is actually attached.
    # `cuda_best_walker_density_histogram` exists as a zero-method stub in the core module,
    # so guard on CUDA availability and attached methods rather than symbol presence.
    if has_cuda() && !isempty(methods(cuda_best_walker_density_histogram))
        counts = cuda_best_walker_density_histogram(best_walkers; n_bins=n_bins, max_walker=max_walker)
    else
        counts = _plain_walker_histogram(best_walkers, n_bins, max_walker)
    end
    edges = range(0, max_walker, length = n_bins + 1)
    return collect(edges), counts
end

# The actual CUDA implementation lives only in the extension (see ext/CUDABackendExt.jl).
# We document the public API here for discoverability.
"""
    cuda_best_walker_density_histogram(best_walkers; n_bins=32, max_walker=2047)

Pure-Julia CUDA implementation (with CPU fallback) of the histogram used for the
"Best Walker Firing Density" panel.

This symbol is only present (and implemented with real @cuda) when the
CUDABackendExt is loaded (i.e. `using CUDA` succeeded in the environment).

Callers should use `walker_density_bins_and_counts` which safely falls back.
See the CUDA section in this file and ext/CUDABackendExt.jl for details.
(Grok Build 0.1 model — part of the #43/#44 combined visuals + runner work.)
"""
function cuda_best_walker_density_histogram end  # provided by extension when available
