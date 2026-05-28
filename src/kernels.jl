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