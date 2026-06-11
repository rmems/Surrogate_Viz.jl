function _cuda_cu(value)
    return getproperty(_cuda_module(), :cu)(value)
end

function _compute_pairwise_deltas_cuda(off_col::AbstractVector, on_col::AbstractVector)
    off_host = Float32.(collect(off_col))
    on_host = Float32.(collect(on_col))
    off_gpu = _cuda_cu(off_host)
    on_gpu = _cuda_cu(on_host)
    deltas_gpu = on_gpu .- off_gpu

    return (
        mean_delta=Float64(mean(deltas_gpu)),
        max_abs_delta=Float64(maximum(abs.(deltas_gpu))),
        final_delta=Float64(last(deltas_gpu)),
    )
end

function _compute_run_stats_cuda(delta_values::AbstractVector, entropy_values::Union{Nothing,AbstractVector})
    delta_host = Float32.(collect(delta_values))
    deltas_gpu = _cuda_cu(delta_host)
    mean_delta = Float64(mean(deltas_gpu))
    max_delta = Float64(maximum(deltas_gpu))
    final_delta = Float64(last(delta_host))

    if entropy_values !== nothing && !isempty(entropy_values)
        entropy_host = Float32.(collect(entropy_values))
        ent_gpu = _cuda_cu(entropy_host)
        mean_entropy = Float64(mean(ent_gpu))
        final_entropy = Float64(last(entropy_host))
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

function _compute_delta_per_tick_cuda(features::AbstractMatrix)
    feat_gpu = _cuda_cu(Float32.(collect(features)))
    deltas_gpu = diff(feat_gpu, dims=1)
    return Array(deltas_gpu)
end

function _compute_delta_per_tick_cuda(timestamps::AbstractVector, features::AbstractMatrix)
    feat_gpu = _cuda_cu(Float32.(collect(features)))
    deltas_gpu = diff(feat_gpu, dims=1)
    return timestamps[2:end], Array(deltas_gpu)
end

function _cuda_best_walker_density_histogram(
    best_walkers::AbstractVector{Int};
    n_bins::Int=32,
    max_walker::Int=2047,
)
    n = length(best_walkers)
    n == 0 && return zeros(Int, n_bins)

    if n > typemax(Int32) || any(w -> w < typemin(Int32) || w > typemax(Int32), best_walkers)
        @warn "CUDA unavailable for walker density histogram inputs outside Int32 range; using CPU fallback"
        return _plain_walker_histogram(best_walkers, n_bins, max_walker)
    end

    walkers_gpu = _cuda_cu(Int32.(collect(best_walkers)))
    bin_size = Float32((max_walker + 1) / n_bins)
    bins_gpu = clamp.(floor.(Int32, walkers_gpu ./ bin_size), 0, Int32(n_bins - 1)) .+ Int32(1)
    bins = Int.(Array(bins_gpu))

    hist = zeros(Int, n_bins)
    for b in bins
        hist[b] += 1
    end
    return hist
end

function compute_pairwise_deltas(
    off_col::AbstractVector,
    on_col::AbstractVector,
    ::CUDABackend,
)
    if !has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return compute_pairwise_deltas(off_col, on_col, CPUBackend())
    end
    return _compute_pairwise_deltas_cuda(off_col, on_col)
end

function compute_run_stats(
    delta_values::AbstractVector,
    entropy_values::Union{Nothing,AbstractVector},
    ::CUDABackend,
)
    if !has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return compute_run_stats(delta_values, entropy_values, CPUBackend())
    end
    return _compute_run_stats_cuda(delta_values, entropy_values)
end

function compute_delta_per_tick(
    features::AbstractMatrix,
    ::CUDABackend,
)
    if !has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return compute_delta_per_tick(features, CPUBackend())
    end
    return _compute_delta_per_tick_cuda(features)
end

function compute_delta_per_tick(
    timestamps::AbstractVector,
    features::AbstractMatrix,
    ::CUDABackend,
)
    if !has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return compute_delta_per_tick(timestamps, features, CPUBackend())
    end
    return _compute_delta_per_tick_cuda(timestamps, features)
end

function cuda_best_walker_density_histogram(
    best_walkers::AbstractVector{Int};
    n_bins::Int=32,
    max_walker::Int=2047,
)
    if !has_cuda()
        @warn "CUDA unavailable; using CPU fallback for walker density histogram"
        return _plain_walker_histogram(best_walkers, n_bins, max_walker)
    end
    return _cuda_best_walker_density_histogram(best_walkers; n_bins=n_bins, max_walker=max_walker)
end
