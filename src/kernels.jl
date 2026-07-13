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

# Core shims for CUDABackend. These methods are always available in the package so
# callers can pass `backend=CUDABackend()` without manually loading `CUDA` first.
# When CUDA is installed and functional, they load the extension and dispatch to the
# GPU implementations; otherwise they fall back to CPUBackend with a warning.
function compute_pairwise_deltas(
    off_col::AbstractVector,
    on_col::AbstractVector,
    ::CUDABackend
)
    if has_cuda()
        ext = Base.get_extension(@__MODULE__, :CUDABackendExt)
        if ext !== nothing
            return Base.invokelatest(compute_pairwise_deltas, off_col, on_col, CUDABackend())
        end
    end
    @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
    return compute_pairwise_deltas(off_col, on_col, CPUBackend())
end

function compute_run_stats(
    delta_values::AbstractVector,
    entropy_values::Union{Nothing,AbstractVector},
    ::CUDABackend
)
    if has_cuda()
        ext = Base.get_extension(@__MODULE__, :CUDABackendExt)
        if ext !== nothing
            return Base.invokelatest(compute_run_stats, delta_values, entropy_values, CUDABackend())
        end
    end
    @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
    return compute_run_stats(delta_values, entropy_values, CPUBackend())
end

function compute_delta_per_tick(
    features::AbstractMatrix,
    ::CUDABackend
)
    if has_cuda()
        ext = Base.get_extension(@__MODULE__, :CUDABackendExt)
        if ext !== nothing
            return Base.invokelatest(compute_delta_per_tick, features, CUDABackend())
        end
    end
    @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
    return compute_delta_per_tick(features, CPUBackend())
end

function compute_delta_per_tick(
    timestamps::AbstractVector,
    features::AbstractMatrix,
    ::CUDABackend
)
    if has_cuda()
        ext = Base.get_extension(@__MODULE__, :CUDABackendExt)
        if ext !== nothing
            return Base.invokelatest(compute_delta_per_tick, timestamps, features, CUDABackend())
        end
    end
    @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
    return compute_delta_per_tick(timestamps, features, CPUBackend())
end

# -----------------------------------------------------------------------------
# Pure Julia CUDA visual kernels (Grok Build 0.1 model)
#
# The CUDA-backed implementations live in ext/CUDABackendExt.jl, a package
# extension that is only loaded when CUDA is loaded by the user. This keeps the
# package loadable and editor-friendly even when CUDA is not installed in the
# active environment.
#
# For standalone scripts and other callers, we always provide a CPU fallback.
# walker_density_bins_and_counts selects the GPU-backed implementation only when
# CUDA is installed and functional.
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
    # `cuda_best_walker_density_histogram` exists as a zero-method stub in the core
    # module until ext/CUDABackendExt.jl adds a method, so guard on CUDA availability
    # and attached methods rather than symbol presence.
    if has_cuda() && !isempty(methods(cuda_best_walker_density_histogram))
        counts = cuda_best_walker_density_histogram(best_walkers; n_bins=n_bins, max_walker=max_walker)
    else
        counts = _plain_walker_histogram(best_walkers, n_bins, max_walker)
    end
    edges = range(0, max_walker, length = n_bins + 1)
    return collect(edges), counts
end

# The CUDA-backed implementation lives in ext/CUDABackendExt.jl.
# We document the public API here for discoverability.
"""
    cuda_best_walker_density_histogram(best_walkers; n_bins=32, max_walker=2047)

Pure-Julia CUDA implementation (with CPU fallback) of the histogram used for the
"Best Walker Firing Density" panel.

When CUDA is not installed or not functional, callers should use
`walker_density_bins_and_counts`, which safely falls back to the CPU path.
See the CUDA section in this file and ext/CUDABackendExt.jl for details.
(Grok Build 0.1 model — part of the #43/#44 combined visuals + runner work.)
"""
function cuda_best_walker_density_histogram end  # provided by extension when available
