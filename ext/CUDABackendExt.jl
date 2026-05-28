module CUDABackendExt

using Statistics

function compute_pairwise_deltas(
    off_col::AbstractVector,
    on_col::AbstractVector,
    ::Core.Type{<:Surrogate_Viz.CUDABackend}
)
    if !Surrogate_Viz.has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return Surrogate_Viz.compute_pairwise_deltas(off_col, on_col, Surrogate_Viz.CPUBackend())
    end
    @eval using CUDA
    off_gpu = CUDA.CuArray(Float32.(off_col))
    on_gpu = CUDA.CuArray(Float32.(on_col))
    deltas_gpu = on_gpu .- off_gpu
    deltas = Array(deltas_gpu)
    return (
        mean_delta = Statistics.mean(deltas),
        max_abs_delta = maximum(abs.(deltas)),
        final_delta = last(deltas),
    )
end

function compute_run_stats(
    delta_values::AbstractVector,
    entropy_values::Union{Nothing,AbstractVector},
    ::Core.Type{<:Surrogate_Viz.CUDABackend}
)
    if !Surrogate_Viz.has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return Surrogate_Viz.compute_run_stats(delta_values, entropy_values, Surrogate_Viz.CPUBackend())
    end
    @eval using CUDA
    deltas_gpu = CUDA.CuArray(Float32.(delta_values))
    mean_delta = Float64(Array(CUDA.sum(deltas_gpu)) / length(deltas_gpu))
    max_delta = Float64(CUDA.maximum(deltas_gpu))
    final_delta = Float64(deltas_gpu[end])

    if entropy_values !== nothing && !isempty(entropy_values)
        ent_gpu = CUDA.CuArray(Float32.(entropy_values))
        mean_entropy = Float64(Array(CUDA.sum(ent_gpu)) / length(ent_gpu))
        final_entropy = Float64(ent_gpu[end])
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
    ::Core.Type{<:Surrogate_Viz.CUDABackend}
)
    if !Surrogate_Viz.has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return Surrogate_Viz.compute_delta_per_tick(features, Surrogate_Viz.CPUBackend())
    end
    @eval using CUDA
    feat_gpu = CUDA.CuArray(Float32.(features))
    deltas_gpu = CUDA.diff(feat_gpu, dims=1)
    return Array(deltas_gpu)
end

function compute_delta_per_tick(
    timestamps::AbstractVector,
    features::AbstractMatrix,
    ::Core.Type{<:Surrogate_Viz.CUDABackend}
)
    if !Surrogate_Viz.has_cuda()
        @warn "CUDABackend requested but CUDA unavailable; using CPUBackend"
        return Surrogate_Viz.compute_delta_per_tick(timestamps, features, Surrogate_Viz.CPUBackend())
    end
    @eval using CUDA
    feat_gpu = CUDA.CuArray(Float32.(features))
    deltas_gpu = CUDA.diff(feat_gpu, dims=1)
    return timestamps[2:end], Array(deltas_gpu)
end

end # module CUDABackendExt