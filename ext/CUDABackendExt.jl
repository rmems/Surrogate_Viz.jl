module CUDABackendExt

using Statistics
using CUDA

const _SV = Base.require(Base.PkgId(Base.UUID("0e7d9c34-7da8-46ec-ad35-4cb1b8ff7bae"), "Surrogate_Viz"))
const _CPUBackend = getfield(_SV, :CPUBackend)
const _CUDABackend = getfield(_SV, :CUDABackend)
const _has_cuda = getfield(_SV, :has_cuda)
const _plain_walker_histogram = getfield(_SV, :_plain_walker_histogram)

function _compute_pairwise_deltas_cuda(off_col::AbstractVector, on_col::AbstractVector)
    off_host = Float32.(collect(off_col))
    on_host = Float32.(collect(on_col))
    off_gpu = CUDA.cu(off_host)
    on_gpu = CUDA.cu(on_host)
    deltas_gpu = on_gpu .- off_gpu

    return (
        mean_delta=Float64(mean(deltas_gpu)),
        max_abs_delta=Float64(maximum(abs.(deltas_gpu))),
        final_delta=Float64(last(on_host) - last(off_host)),
    )
end

function _compute_run_stats_cuda(delta_values::AbstractVector, entropy_values::Union{Nothing,AbstractVector})
    delta_host = Float32.(collect(delta_values))
    deltas_gpu = CUDA.cu(delta_host)
    mean_delta = Float64(mean(deltas_gpu))
    max_delta = Float64(maximum(deltas_gpu))
    final_delta = Float64(last(delta_host))

    if entropy_values !== nothing && !isempty(entropy_values)
        entropy_host = Float32.(collect(entropy_values))
        ent_gpu = CUDA.cu(entropy_host)
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
    feat_gpu = CUDA.cu(Float32.(collect(features)))
    deltas_gpu = diff(feat_gpu, dims=1)
    return Array(deltas_gpu)
end

function _compute_delta_per_tick_cuda(timestamps::AbstractVector, features::AbstractMatrix)
    feat_gpu = CUDA.cu(Float32.(collect(features)))
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

    d_walkers = CUDA.cu(Int32.(collect(best_walkers)))
    d_hist = CUDA.zeros(Int32, n_bins)

    bin_size = (max_walker + 1) / n_bins

    function hist_kernel(walkers, hist, bin_size_f, n_items)
        i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
        if i <= n_items
            w = walkers[i]
            b = clamp(floor(Int, w / bin_size_f), 0, n_bins - 1) + 1
            CUDA.@atomic hist[b] += Int32(1)
        end
    end

    threads = 256
    blocks = min(1024, cld(n, threads))
    CUDA.@cuda threads = threads blocks = blocks hist_kernel(d_walkers, d_hist, Float32(bin_size), n)

    return Int.(Array(d_hist))
end

@eval _SV begin
    function compute_pairwise_deltas(
        off_col::AbstractVector,
        on_col::AbstractVector,
        ::$(_CUDABackend)
    )
        if !$(_has_cuda)()
            @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
            return compute_pairwise_deltas(off_col, on_col, $(_CPUBackend)())
        end
        return $(_compute_pairwise_deltas_cuda)(off_col, on_col)
    end

    function compute_run_stats(
        delta_values::AbstractVector,
        entropy_values::Union{Nothing,AbstractVector},
        ::$(_CUDABackend)
    )
        if !$(_has_cuda)()
            @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
            return compute_run_stats(delta_values, entropy_values, $(_CPUBackend)())
        end
        return $(_compute_run_stats_cuda)(delta_values, entropy_values)
    end

    function compute_delta_per_tick(
        features::AbstractMatrix,
        ::$(_CUDABackend)
    )
        if !$(_has_cuda)()
            @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
            return compute_delta_per_tick(features, $(_CPUBackend)())
        end
        return $(_compute_delta_per_tick_cuda)(features)
    end

    function compute_delta_per_tick(
        timestamps::AbstractVector,
        features::AbstractMatrix,
        ::$(_CUDABackend)
    )
        if !$(_has_cuda)()
            @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
            return compute_delta_per_tick(timestamps, features, $(_CPUBackend)())
        end
        return $(_compute_delta_per_tick_cuda)(timestamps, features)
    end

    function cuda_best_walker_density_histogram(
        best_walkers::AbstractVector{Int};
        n_bins::Int=32,
        max_walker::Int=2047,
    )
        if !$(_has_cuda)()
            @warn "CUDABackend requested but CUDA unavailable; using CPU fallback for visual kernel"
            return $(_plain_walker_histogram)(best_walkers, n_bins, max_walker)
        end
        return $(_cuda_best_walker_density_histogram)(;
            best_walkers=best_walkers,
            n_bins=n_bins,
            max_walker=max_walker,
        )
    end
end

end # module CUDABackendExt
