module CUDABackendExt

using Statistics
using CUDA
using Surrogate_Viz

function Surrogate_Viz.compute_pairwise_deltas(
    off_col::AbstractVector,
    on_col::AbstractVector,
    ::Surrogate_Viz.CUDABackend
)
    if !Surrogate_Viz.has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return Surrogate_Viz.compute_pairwise_deltas(off_col, on_col, Surrogate_Viz.CPUBackend())
    end
    off_gpu = CUDA.CuArray(Float32.(off_col))
    on_gpu = CUDA.CuArray(Float32.(on_col))
    deltas_gpu = on_gpu .- off_gpu
    return (
        mean_delta = Float64(mean(deltas_gpu)),
        max_abs_delta = Float64(maximum(abs.(deltas_gpu))),
        final_delta = Float64(CUDA.@allowscalar deltas_gpu[end]),
    )
end

function Surrogate_Viz.compute_run_stats(
    delta_values::AbstractVector,
    entropy_values::Union{Nothing,AbstractVector},
    ::Surrogate_Viz.CUDABackend
)
    if !Surrogate_Viz.has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return Surrogate_Viz.compute_run_stats(delta_values, entropy_values, Surrogate_Viz.CPUBackend())
    end
    deltas_gpu = CUDA.CuArray(Float32.(delta_values))
    mean_delta = Float64(mean(deltas_gpu))
    max_delta = Float64(maximum(deltas_gpu))
    final_delta = Float64(CUDA.@allowscalar deltas_gpu[end])

    if entropy_values !== nothing && !isempty(entropy_values)
        ent_gpu = CUDA.CuArray(Float32.(entropy_values))
        mean_entropy = Float64(mean(ent_gpu))
        final_entropy = Float64(CUDA.@allowscalar ent_gpu[end])
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

function Surrogate_Viz.compute_delta_per_tick(
    features::AbstractMatrix,
    ::Surrogate_Viz.CUDABackend
)
    if !Surrogate_Viz.has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return Surrogate_Viz.compute_delta_per_tick(features, Surrogate_Viz.CPUBackend())
    end
    feat_gpu = CUDA.CuArray(Float32.(features))
    deltas_gpu = diff(feat_gpu, dims=1)
    return Array(deltas_gpu)
end

function Surrogate_Viz.compute_delta_per_tick(
    timestamps::AbstractVector,
    features::AbstractMatrix,
    ::Surrogate_Viz.CUDABackend
)
    if !Surrogate_Viz.has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return Surrogate_Viz.compute_delta_per_tick(timestamps, features, Surrogate_Viz.CPUBackend())
    end
    feat_gpu = CUDA.CuArray(Float32.(features))
    deltas_gpu = diff(feat_gpu, dims=1)
    return timestamps[2:end], Array(deltas_gpu)
end

end # module CUDABackendExt