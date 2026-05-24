# SurrogateViz — shared utilities for SAAQ comparison scripts

module SurrogateViz

using CSV
using DataFrames
using Statistics

const IMPORT_ROOT = joinpath(@__DIR__, "..", "data", "corinth_runs")

function imported_latent_path(run::Dict{String,<:Any})
    joinpath(IMPORT_ROOT, run["model"], run["telemetry_source"], run["heartbeat"], run["id"], "latent_telemetry.csv")
end

function load_latent_df(run::Dict{String,<:Any})
    path = imported_latent_path(run)
    isfile(path) || error("Imported latent telemetry not found at $(path). Run `julia import_corinth_runs.jl` first.")
    df = CSV.read(path, DataFrame)
    "timestamp_ms" in names(df) || error("Missing timestamp_ms column in $(path)")
    sort!(df, :timestamp_ms)
    return df
end

function detect_delta_column(frames::Vector{DataFrame})
    isempty(frames) && error("detect_delta_column: no frames provided")
    common_names = intersect((Set(String.(names(df))) for df in frames)...)
    "saaq_delta_q_v15_target" in common_names && return :saaq_delta_q_v15_target

    best_name = nothing
    best_score = -typemax(Int)
    for name in common_names
        lower_name = lowercase(name)
        occursin("saaq", lower_name) || continue
        occursin("delta", lower_name) || continue
        occursin("target", lower_name) || continue

        score = 0
        occursin("v15", lower_name) && (score += 100)
        occursin("legacy", lower_name) && (score -= 25)
        occursin("delta_q", lower_name) && (score += 10)
        startswith(lower_name, "saaq_delta_q") && (score += 5)

        if score > best_score
            best_score = score
            best_name = Symbol(name)
        end
    end

    best_name === nothing && error("Could not find a SAAQ target delta column in imported latent telemetry")
    return best_name
end

function maybe_entropy_column(frames::Vector{DataFrame})
    isempty(frames) && return nothing
    common_names = intersect((Set(String.(names(df))) for df in frames)...)
    return "routing_entropy" in common_names ? :routing_entropy : nothing
end

to_float64_vec(col) = Float64[Float64(v) for v in skipmissing(col)]
to_int_ms(v) = Int(round(Float64(v)))

function summarise_run(df::DataFrame, run::Dict{String,<:Any}, delta_col::Symbol, entropy_col::Union{Nothing,Symbol})
    nrow(df) > 0 || error("summarise_run: empty DataFrame for run id=$(run["id"]) heartbeat=$(run["heartbeat"])")

    delta_values = to_float64_vec(df[!, delta_col])
    isempty(delta_values) && error("summarise_run: column $(delta_col) is empty after dropping missing values for run $(run["id"])")

    row = Dict{String,Any}(
        "run_id" => run["id"],
        "heartbeat" => run["heartbeat"],
        "rows" => nrow(df),
        "first_ms" => to_int_ms(first(df.timestamp_ms)),
        "last_ms" => to_int_ms(last(df.timestamp_ms)),
        "mean_delta" => Statistics.mean(delta_values),
        "max_delta" => maximum(delta_values),
        "final_delta" => last(delta_values),
    )

    if entropy_col !== nothing
        entropy_values = to_float64_vec(df[!, entropy_col])
        if isempty(entropy_values)
            row["mean_entropy"] = missing
            row["final_entropy"] = missing
        else
            row["mean_entropy"] = Statistics.mean(entropy_values)
            row["final_entropy"] = last(entropy_values)
        end
    else
        row["mean_entropy"] = missing
        row["final_entropy"] = missing
    end

    return row
end

function pairwise_summary(off_df::DataFrame, on_df::DataFrame, delta_col::Symbol, entropy_col::Union{Nothing,Symbol})
    joined = innerjoin(
        select(off_df, :timestamp_ms, delta_col => :delta_off, (entropy_col === nothing ? [] : [entropy_col => :entropy_off])...),
        select(on_df, :timestamp_ms, delta_col => :delta_on, (entropy_col === nothing ? [] : [entropy_col => :entropy_on])...),
        on = :timestamp_ms,
    )

    nrow(joined) > 0 || error("No overlapping timestamps between heartbeat_off and heartbeat_on runs")
    joined.delta_on_minus_off = joined.delta_on .- joined.delta_off

    summary = Dict{String,Any}(
        "paired_rows" => nrow(joined),
        "mean_delta_on_minus_off" => Statistics.mean(joined.delta_on_minus_off),
        "max_abs_delta_on_minus_off" => maximum(abs.(joined.delta_on_minus_off)),
        "final_delta_on_minus_off" => last(joined.delta_on_minus_off),
    )

    if entropy_col !== nothing
        joined.entropy_on_minus_off = joined.entropy_on .- joined.entropy_off
        summary["mean_entropy_on_minus_off"] = Statistics.mean(joined.entropy_on_minus_off)
        summary["final_entropy_on_minus_off"] = last(joined.entropy_on_minus_off)
    end

    return joined, summary
end

fmt(x::Missing) = "-"
function fmt(x::Real)
    rounded = round(Float64(x); digits = 6)
    return string(rounded)
end
fmt(x) = string(x)

export imported_latent_path, load_latent_df, detect_delta_column, maybe_entropy_column
export to_float64_vec, to_int_ms, summarise_run, pairwise_summary, fmt
export IMPORT_ROOT

end # module SurrogateViz
