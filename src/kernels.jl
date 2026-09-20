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
            return Base.invokelatest(ext._compute_pairwise_deltas_cuda, off_col, on_col)
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
            return Base.invokelatest(ext._compute_run_stats_cuda, delta_values, entropy_values)
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
            return Base.invokelatest(ext._compute_delta_per_tick_cuda, features)
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
            return Base.invokelatest(ext._compute_delta_per_tick_cuda, timestamps, features)
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

"""
    _walker_histogram_dispatch(best_walkers, n_bins, max_walker) -> Vector{Int}

Choose the GPU or CPU walker-density histogram and say so when the GPU path is
skipped.

The two public entry points below previously had their own copies of this
selection logic and disagreed about it: `walker_density_bins_and_counts` fell
back to the CPU silently, while every other backend dispatcher in this file
warns, and `cuda_best_walker_density_histogram` warned with text that was wrong
in one of its two fallback cases. Both now route through here so the behaviour
cannot drift apart again.

The two reasons for falling back are reported distinctly, because they call for
different action: "CUDA is not functional" is a host or driver problem, while
"the extension is not loaded" just means nothing has run `using CUDA` in this
session and the GPU is probably fine.
"""
function _walker_histogram_dispatch(best_walkers::AbstractVector{Int}, n_bins::Int, max_walker::Int)
    if !has_cuda()
        @warn "CUDA is not functional; using CPU fallback for the walker density histogram" maxlog = 1
        return _plain_walker_histogram(best_walkers, n_bins, max_walker)
    end

    # Prefer the CUDA version only when the package extension is actually attached.
    # Use Base.invokelatest to avoid world-age issues when the extension is loaded
    # dynamically (e.g., first call in a fresh process).
    ext = Base.get_extension(@__MODULE__, :CUDABackendExt)
    if ext === nothing
        @warn "CUDA is functional but the CUDABackendExt extension is not loaded; using CPU fallback for the walker density histogram. Run `using CUDA` to enable the GPU path." maxlog = 1
        return _plain_walker_histogram(best_walkers, n_bins, max_walker)
    end

    return Base.invokelatest(ext._cuda_best_walker_density_histogram, best_walkers; n_bins=n_bins, max_walker=max_walker)
end

function walker_density_bins_and_counts(
    best_walkers::AbstractVector{Int};
    n_bins::Int = 32,
    max_walker::Int = 2047
)
    counts = _walker_histogram_dispatch(best_walkers, n_bins, max_walker)
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
function cuda_best_walker_density_histogram(
    best_walkers::AbstractVector{Int};
    n_bins::Int = 32,
    max_walker::Int = 2047
)
    return _walker_histogram_dispatch(best_walkers, n_bins, max_walker)
end

# -----------------------------------------------------------------------------
# Path raster + spiking overlay (Grok Build 0.1 model, Linear RM-62 / GH#43)
#
# The original CUDA visual issue asked for more than the 1-D walker-density
# histogram: a 2-D density raster for "SNN Routing Path Over Time" and a
# NaN-robust spiking overlay. Both follow the same has_cuda + extension
# dispatch as the histogram. Quiet ticks (firing=0, entropy=1.0) stay in the
# picture as zeros; non-finite values never appear in the returned grids.
# -----------------------------------------------------------------------------

"""
    is_finite_visual(x) -> Bool

True when `x` can be placed on a PNG without introducing NaN artifacts.

Missing, NaN, and Inf are rejected. Quiet first-exp ticks (firing rate 0.0,
routing_entropy=1.0) are finite and kept — those are real idle samples, not
holes in the raster.
"""
is_finite_visual(::Missing) = false
is_finite_visual(x::Number) = isfinite(float(x))
is_finite_visual(_) = false

function _visual_floats(xs::AbstractVector)
    n = length(xs)
    out = Vector{Float64}(undef, n)
    @inbounds for i in 1:n
        x = xs[i]
        out[i] = is_finite_visual(x) ? Float64(x) : NaN
    end
    return out
end

function _raster_geometry(
    ticks::AbstractVector{<:Real},
    n_tick_bins::Int,
    n_walker_bins::Int,
    max_walker::Int,
)
    n_tick_bins < 1 && error("n_tick_bins must be ≥ 1")
    n_walker_bins < 1 && error("n_walker_bins must be ≥ 1")
    max_walker < 0 && error("max_walker must be ≥ 0")

    tmin = Inf
    tmax = -Inf
    for t in ticks
        isfinite(t) || continue
        t < tmin && (tmin = Float64(t))
        t > tmax && (tmax = Float64(t))
    end
    if !isfinite(tmin)
        tmin = 0.0
        tmax = 1.0
    elseif tmin == tmax
        tmax = tmin + 1.0
    end
    tick_inv = n_tick_bins / (tmax - tmin)
    walker_bin_size = (max_walker + 1) / n_walker_bins
    tick_edges = collect(range(tmin, tmax; length = n_tick_bins + 1))
    walker_edges = collect(range(0.0, Float64(max_walker); length = n_walker_bins + 1))
    return tmin, tick_inv, walker_bin_size, tick_edges, walker_edges
end

function _bin_tick_walker(t::Float64, w::Float64, tmin, tick_inv, walker_bin_size, n_tick_bins, n_walker_bins)
    tb = clamp(floor(Int, (t - tmin) * tick_inv), 0, n_tick_bins - 1) + 1
    wb = clamp(floor(Int, w / walker_bin_size), 0, n_walker_bins - 1) + 1
    return wb, tb
end

function _plain_path_raster(
    ticks::AbstractVector,
    walkers::AbstractVector;
    n_tick_bins::Int = 256,
    n_walker_bins::Int = 128,
    max_walker::Int = 2047,
)
    length(ticks) == length(walkers) || error("prepare_path_raster: ticks and walkers must have the same length")
    tf = _visual_floats(ticks)
    wf = _visual_floats(walkers)
    tmin, tick_inv, walker_bin_size, tick_edges, walker_edges =
        _raster_geometry(tf, n_tick_bins, n_walker_bins, max_walker)
    counts = zeros(Int, n_walker_bins, n_tick_bins)
    @inbounds for i in eachindex(tf)
        t = tf[i]
        w = wf[i]
        (isfinite(t) && isfinite(w)) || continue
        wb, tb = _bin_tick_walker(t, w, tmin, tick_inv, walker_bin_size, n_tick_bins, n_walker_bins)
        counts[wb, tb] += 1
    end
    return (; tick_edges, walker_edges, counts)
end

function _plain_spike_overlay(
    ticks::AbstractVector,
    walkers::AbstractVector,
    weights::AbstractVector;
    n_tick_bins::Int = 256,
    n_walker_bins::Int = 128,
    max_walker::Int = 2047,
)
    length(ticks) == length(walkers) || error("prepare_spike_overlay: ticks and walkers must have the same length")
    length(weights) == length(ticks) || error("prepare_spike_overlay: weights must have the same length as ticks")
    tf = _visual_floats(ticks)
    wf = _visual_floats(walkers)
    fire = _visual_floats(weights)
    tmin, tick_inv, walker_bin_size, tick_edges, walker_edges =
        _raster_geometry(tf, n_tick_bins, n_walker_bins, max_walker)
    sums = zeros(Float64, n_walker_bins, n_tick_bins)
    counts = zeros(Int, n_walker_bins, n_tick_bins)
    @inbounds for i in eachindex(tf)
        t = tf[i]
        w = wf[i]
        (isfinite(t) && isfinite(w)) || continue
        f = fire[i]
        isfinite(f) || continue
        wb, tb = _bin_tick_walker(t, w, tmin, tick_inv, walker_bin_size, n_tick_bins, n_walker_bins)
        sums[wb, tb] += f
        counts[wb, tb] += 1
    end
    intensity = zeros(Float64, n_walker_bins, n_tick_bins)
    @inbounds for i in eachindex(counts)
        c = counts[i]
        c == 0 || (intensity[i] = sums[i] / c)
    end
    return (; tick_edges, walker_edges, intensity)
end

"""
    _visual_kernel_dispatch(cpu_fn, gpu_fn, args...; kernel_label, kwargs...)

Shared has_cuda / extension selection for the PNG visual kernels. Walker
density keeps its own dispatcher so its pinned warning text cannot drift;
path raster and spike overlay reuse this helper.
"""
function _visual_kernel_dispatch(cpu_fn, gpu_fn::Symbol, args...; kernel_label::String, kwargs...)
    if !has_cuda()
        @warn "CUDA is not functional; using CPU fallback for the $kernel_label" maxlog = 1
        return cpu_fn(args...; kwargs...)
    end
    ext = Base.get_extension(@__MODULE__, :CUDABackendExt)
    if ext === nothing
        @warn "CUDA is functional but the CUDABackendExt extension is not loaded; using CPU fallback for the $kernel_label. Run `using CUDA` to enable the GPU path." maxlog = 1
        return cpu_fn(args...; kwargs...)
    end
    return Base.invokelatest(getproperty(ext, gpu_fn), args...; kwargs...)
end

"""
    prepare_path_raster(ticks, walkers, backend=CUDABackend(); n_tick_bins=256, n_walker_bins=128, max_walker=2047)

2-D occupancy raster of `(tick, best_walker)` for the "SNN Routing Path Over
Time" panel. Non-finite coordinates are skipped. `CPUBackend()` forces the
plain-Julia path with no warning; `CUDABackend()` uses the `@cuda` atomic
histogram when the extension is loaded.
"""
function prepare_path_raster(
    ticks::AbstractVector,
    walkers::AbstractVector,
    ::CPUBackend;
    n_tick_bins::Int = 256,
    n_walker_bins::Int = 128,
    max_walker::Int = 2047,
)
    return _plain_path_raster(ticks, walkers; n_tick_bins, n_walker_bins, max_walker)
end

function prepare_path_raster(
    ticks::AbstractVector,
    walkers::AbstractVector,
    ::CUDABackend;
    n_tick_bins::Int = 256,
    n_walker_bins::Int = 128,
    max_walker::Int = 2047,
)
    return _visual_kernel_dispatch(
        _plain_path_raster,
        :_cuda_prepare_path_raster,
        ticks,
        walkers;
        kernel_label = "path raster",
        n_tick_bins,
        n_walker_bins,
        max_walker,
    )
end

function prepare_path_raster(ticks::AbstractVector, walkers::AbstractVector; kwargs...)
    return prepare_path_raster(ticks, walkers, CUDABackend(); kwargs...)
end

"""
    prepare_spike_overlay(ticks, walkers, weights, backend=CUDABackend(); kwargs...)

Mean finite weight per `(tick, walker)` bin for the spiking overlay heatmap.
Non-finite weights (literal NaN in corinth latent CSVs) are omitted from the
mean so empty / quiet bins stay 0.0, never NaN. When `weights` is omitted, each
walker visit counts as a spike of weight 1 (the first-exp "walker is a
spike" reading).
"""
function prepare_spike_overlay(
    ticks::AbstractVector,
    walkers::AbstractVector,
    weights::AbstractVector,
    ::CPUBackend;
    n_tick_bins::Int = 256,
    n_walker_bins::Int = 128,
    max_walker::Int = 2047,
)
    return _plain_spike_overlay(ticks, walkers, weights; n_tick_bins, n_walker_bins, max_walker)
end

function prepare_spike_overlay(
    ticks::AbstractVector,
    walkers::AbstractVector,
    weights::AbstractVector,
    ::CUDABackend;
    n_tick_bins::Int = 256,
    n_walker_bins::Int = 128,
    max_walker::Int = 2047,
)
    return _visual_kernel_dispatch(
        _plain_spike_overlay,
        :_cuda_prepare_spike_overlay,
        ticks,
        walkers,
        weights;
        kernel_label = "spike overlay",
        n_tick_bins,
        n_walker_bins,
        max_walker,
    )
end

function prepare_spike_overlay(
    ticks::AbstractVector,
    walkers::AbstractVector,
    weights::AbstractVector;
    kwargs...,
)
    return prepare_spike_overlay(ticks, walkers, weights, CUDABackend(); kwargs...)
end

function prepare_spike_overlay(
    ticks::AbstractVector,
    walkers::AbstractVector,
    backend::ComputeBackend;
    kwargs...,
)
    return prepare_spike_overlay(ticks, walkers, ones(Float64, length(ticks)), backend; kwargs...)
end

function prepare_spike_overlay(ticks::AbstractVector, walkers::AbstractVector; kwargs...)
    return prepare_spike_overlay(ticks, walkers, CUDABackend(); kwargs...)
end
