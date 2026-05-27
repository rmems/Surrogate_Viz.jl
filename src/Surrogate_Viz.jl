# SurrogateViz — shared utilities for SAAQ comparison scripts

module Surrogate_Viz

using CSV
using DataFrames
using JSON
using Statistics

const IMPORT_ROOT = normpath(joinpath(@__DIR__, "..", "data", "corinth_runs"))

function validate_path_component(name::AbstractString, value::AbstractString)
    occursin("..", value) && error("Invalid $(name) path component (contains '..'): $(value)")
    (startswith(value, "/") || occursin("\\", value)) && error("Invalid $(name) path component (absolute or contains backslash): $(value)")
    return value
end

function imported_latent_path(run::Dict{String,<:Any})
    model = validate_path_component("model", run["model"])
    src = validate_path_component("telemetry_source", run["telemetry_source"])
    cond = validate_path_component("condition", run["condition"])
    id = validate_path_component("id", run["id"])
    joinpath(IMPORT_ROOT, model, src, cond, id, "latent_telemetry.csv")
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
    nrow(df) > 0 || error("summarise_run: empty DataFrame for run id=$(run["id"]) condition=$(run["condition"])")

    delta_values = to_float64_vec(df[!, delta_col])
    isempty(delta_values) && error("summarise_run: column $(delta_col) is empty after dropping missing values for run $(run["id"])")

    row = Dict{String,Any}(
        "run_id" => run["id"],
        "condition" => run["condition"],
        "rows" => nrow(df),
        "first_ms" => to_int_ms(first(df[!, :timestamp_ms])),
        "last_ms" => to_int_ms(last(df[!, :timestamp_ms])),
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

    nrow(joined) > 0 || error("No overlapping timestamps between the provided runs")
    joined.delta_on_minus_off = joined.delta_on .- joined.delta_off

    summary = Dict{String,Any}(
        "paired_rows" => nrow(joined),
        "mean_delta_on_minus_off" => Statistics.mean(joined.delta_on_minus_off),
        "max_abs_delta_on_minus_off" => maximum(abs.(joined.delta_on_minus_off)),
        "final_delta_on_minus_off" => last(joined.delta_on_minus_off),
    )

    if entropy_col !== nothing
        joined.entropy_on_minus_off = joined.entropy_on .- joined.entropy_off
        emv = to_float64_vec(joined.entropy_on_minus_off)
        if isempty(emv)
            summary["mean_entropy_on_minus_off"] = missing
            summary["final_entropy_on_minus_off"] = missing
        else
            summary["mean_entropy_on_minus_off"] = Statistics.mean(emv)
            summary["final_entropy_on_minus_off"] = last(emv)
        end
    end

    return joined, summary
end

fmt(x::Missing) = "-"
function fmt(x::Real)
    rounded = round(Float64(x); digits = 6)
    rounded == 0.0 && (rounded = 0.0)
    return string(rounded)
end
fmt(x) = string(x)

@enum RunStatus real synthetic skipped failed

Base.@kwdef struct RunManifest
    run_id::String
    run_status::RunStatus = real
    model_family::String
    model_slug::String = ""
    model_descriptor::String = ""
    architecture::String = ""
    checkpoint_format::String = ""
    prompt_profile::String = ""
    saaq_rule::String = ""
    saaq_dual_emit::Bool = false
    telemetry_source::String = ""
    routing_mode::String = ""
    heartbeat_enabled::Bool = false
    heartbeat_amplitude::Float64 = 0.0
    heartbeat_period_ticks::Int = 0
    heartbeat_duty_cycle::Float64 = 0.0
    run_tag::String = ""
    repeat_idx::Int = 0
    repeat_count::Int = 1
    validation_status::String = "unknown"
    error::Union{Nothing,String} = nothing
    ticks::Int = 0
    ticks_effective::Int = 0
    extra::Dict{String,Any} = Dict{String,Any}()
end

Base.@kwdef struct RunMetrics
    ticks_completed::Int = 0
    latent_rows::Int = 0
    mean_tick_elapsed_us::Union{Float64,Missing} = missing
    first_timestamp_ms::Union{Int,Missing} = missing
    last_timestamp_ms::Union{Int,Missing} = missing
    repeat_determinism::Union{String,Missing} = missing
    extra::Dict{String,Any} = Dict{String,Any}()
end

Base.@kwdef struct RunWarning
    category::String = ""
    message::String = ""
    tensor_name::Union{String,Nothing} = nothing
end

Base.@kwdef struct SaaqBundle
    manifest::RunManifest
    metrics::RunMetrics
    warnings::Vector{RunWarning} = RunWarning[]
end

KNOWN_MANIFEST_FIELDS = [
    :run_id, :model_slug, :model_family, :architecture, :checkpoint_path,
    :routing_tensor_name, :synapse_source, :checkpoint_format, :prompt_embedding_source,
    :prompt_profile, :prompt_text, :ticks, :saaq_rule, :saaq_primary_rule,
    :saaq_dual_emit, :validation_status, :error, :heartbeat_enabled,
    :heartbeat_amplitude, :heartbeat_period_ticks, :heartbeat_duty_cycle,
    :heartbeat_phase_offset_ticks, :telemetry_source, :telemetry_csv_path,
    :telemetry_row_count, :wraparound_enabled, :wraparound_loops,
:ticks_effective, :run_dir, :output_root, :repeat_idx,
    :repeat_count, :cwd_routing_csv_contaminated, :run_tag, :routing_mode,
    :generated_files, :created_at, :repo, :commit_sha,
]

KNOWN_METRICS_FIELDS = [
    :ticks_completed, :latent_rows, :mean_tick_elapsed_us,
    :first_timestamp_ms, :last_timestamp_ms, :repeat_determinism,
]

function _status_from_validation(v::Union{Nothing,String}, error::Union{Nothing,String})
    if v === nothing
        return error !== nothing && !isempty(error) ? failed : real
    elseif v ∈ ("completed", "success")
        return real
    elseif v ∈ ("synthetic",)
        return synthetic
    elseif v ∈ ("skipped", "skip")
        return skipped
    elseif v ∈ ("failed", "error", "crash")
        return failed
    elseif error !== nothing && !isempty(error)
        return failed
    else
        return real
    end
end

function load_saaq_bundle(path::AbstractString)::SaaqBundle
    manifest_path = joinpath(path, "run_manifest.json")
    summary_path = joinpath(path, "summary.json")

    if !isfile(manifest_path)
        error("Bundle validation failed: run_manifest.json not found at $(manifest_path)")
    end

    raw_manifest = JSON.parsefile(manifest_path)

    extra_manifest = Dict{String,Any}()
    for (k, v) in raw_manifest
        Symbol(k) in KNOWN_MANIFEST_FIELDS || (extra_manifest[k] = v)
    end

    validation_status = get(raw_manifest, "validation_status", "unknown")
    run_error = get(raw_manifest, "error", nothing)
    run_status = _status_from_validation(validation_status, run_error)

    manifest = RunManifest(
        run_id = get(raw_manifest, "run_id", ""),
        run_status = run_status,
        model_family = get(raw_manifest, "model_family", ""),
        model_slug = get(raw_manifest, "model_slug", ""),
        model_descriptor = get(raw_manifest, "checkpoint_path", ""),
        architecture = get(raw_manifest, "architecture", ""),
        checkpoint_format = get(raw_manifest, "checkpoint_format", ""),
        prompt_profile = get(raw_manifest, "prompt_profile", ""),
        saaq_rule = get(raw_manifest, "saaq_rule", ""),
        saaq_dual_emit = get(raw_manifest, "saaq_dual_emit", false),
        telemetry_source = get(raw_manifest, "telemetry_source", ""),
        routing_mode = get(raw_manifest, "routing_mode", ""),
        heartbeat_enabled = get(raw_manifest, "heartbeat_enabled", false),
        heartbeat_amplitude = get(raw_manifest, "heartbeat_amplitude", 0.0),
        heartbeat_period_ticks = get(raw_manifest, "heartbeat_period_ticks", 0),
        heartbeat_duty_cycle = get(raw_manifest, "heartbeat_duty_cycle", 0.0),
        run_tag = get(raw_manifest, "run_tag", ""),
        repeat_idx = get(raw_manifest, "repeat_idx", 0),
        repeat_count = get(raw_manifest, "repeat_count", 1),
        validation_status = validation_status,
        error = run_error,
        ticks = get(raw_manifest, "ticks", 0),
        ticks_effective = get(raw_manifest, "ticks_effective", 0),
        extra = extra_manifest,
    )

    metrics = RunMetrics()
    warnings = RunWarning[]

    if isfile(summary_path)
        raw_summary = JSON.parsefile(summary_path)

        extra_metrics = Dict{String,Any}()
        metrics_inner = get(raw_summary, "metrics", raw_summary)
        for (k, v) in metrics_inner
            Symbol(k) in KNOWN_METRICS_FIELDS || (extra_metrics[k] = v)
        end

        raw_metrics = get(raw_summary, "metrics", Dict{String,Any}())
        metrics = RunMetrics(
            ticks_completed = get(raw_metrics, "ticks_completed", 0),
            latent_rows = get(raw_metrics, "latent_rows", 0),
            mean_tick_elapsed_us = get(raw_metrics, "mean_tick_elapsed_us", missing),
            first_timestamp_ms = get(raw_metrics, "first_timestamp_ms", missing),
            last_timestamp_ms = get(raw_metrics, "last_timestamp_ms", missing),
            repeat_determinism = get(raw_metrics, "repeat_determinism", missing),
            extra = extra_metrics,
        )
    end

    return SaaqBundle(manifest, metrics, warnings)
end

function validate_saaq_bundle(path::AbstractString)::Tuple{Bool, Vector{String}}
    errors = String[]
    manifest_path = joinpath(path, "run_manifest.json")
    if !isfile(manifest_path)
        push!(errors, "run_manifest.json not found at $(manifest_path)")
        return false, errors
    end
    try
        raw = JSON.parsefile(manifest_path)
        if !haskey(raw, "run_id")
            push!(errors, "run_manifest.json missing required field: run_id")
        end
        if !haskey(raw, "run_dir")
            push!(errors, "run_manifest.json missing required field: run_dir")
        end
    catch e
        push!(errors, "run_manifest.json is not valid JSON: $(e)")
    end
    return isempty(errors), errors
end

function _nothing_to_missing(v::Union{Nothing,T}) where T
    v === nothing ? missing : v
end

function normalize_bundle_to_tables(bundle::SaaqBundle)::Tuple{DataFrame, DataFrame, DataFrame}
    m = bundle.manifest
    metrics_row = bundle.metrics

    run_status_str = string(m.run_status)

    runs_row = Dict{String,Any}(
        "run_id" => m.run_id,
        "run_status" => run_status_str,
        "model_family" => m.model_family,
        "model_slug" => m.model_slug,
        "model_descriptor" => _nothing_to_missing(m.model_descriptor),
        "architecture" => m.architecture,
        "checkpoint_format" => m.checkpoint_format,
        "prompt_profile" => m.prompt_profile,
        "saaq_formula_version" => m.saaq_rule,
        "saaq_dual_emit" => m.saaq_dual_emit,
        "telemetry_source" => m.telemetry_source,
        "routing_mode" => m.routing_mode,
        "heartbeat_enabled" => m.heartbeat_enabled,
        "heartbeat_amplitude" => m.heartbeat_amplitude,
        "heartbeat_period_ticks" => m.heartbeat_period_ticks,
        "heartbeat_duty_cycle" => m.heartbeat_duty_cycle,
        "run_tag" => m.run_tag,
        "repeat_idx" => m.repeat_idx,
        "repeat_count" => m.repeat_count,
        "validation_status" => m.validation_status,
        "error" => _nothing_to_missing(m.error),
        "ticks" => m.ticks,
        "ticks_effective" => m.ticks_effective,
    )

    if !isempty(m.extra)
        for (k, v) in m.extra
            clean_v = v === nothing ? missing :
                      v isa AbstractArray ? Any[vi === nothing ? missing : vi for vi in v] :
                      v
            runs_row["extra_$(k)"] = clean_v
        end
    end

    runs_df = DataFrame([runs_row])

    metrics_rows = Dict{String,Any}[]
    for (k, v) in metrics_row.extra
        push!(metrics_rows, Dict{String,Any}(
            "run_id" => m.run_id,
            "metric_name" => k,
            "metric_value" => v,
            "metric_category" => "extra",
        ))
    end

    if metrics_row.ticks_completed > 0
        push!(metrics_rows, Dict{String,Any}(
            "run_id" => m.run_id, "metric_name" => "ticks_completed",
            "metric_value" => metrics_row.ticks_completed, "metric_category" => "runtime"))
    end
    if metrics_row.latent_rows > 0
        push!(metrics_rows, Dict{String,Any}(
            "run_id" => m.run_id, "metric_name" => "latent_rows",
            "metric_value" => metrics_row.latent_rows, "metric_category" => "runtime"))
    end
    if !ismissing(metrics_row.mean_tick_elapsed_us)
        push!(metrics_rows, Dict{String,Any}(
            "run_id" => m.run_id, "metric_name" => "mean_tick_elapsed_us",
            "metric_value" => metrics_row.mean_tick_elapsed_us, "metric_category" => "runtime"))
    end
    if !ismissing(metrics_row.first_timestamp_ms)
        push!(metrics_rows, Dict{String,Any}(
            "run_id" => m.run_id, "metric_name" => "first_timestamp_ms",
            "metric_value" => metrics_row.first_timestamp_ms, "metric_category" => "runtime"))
    end
    if !ismissing(metrics_row.last_timestamp_ms)
        push!(metrics_rows, Dict{String,Any}(
            "run_id" => m.run_id, "metric_name" => "last_timestamp_ms",
            "metric_value" => metrics_row.last_timestamp_ms, "metric_category" => "runtime"))
    end
    if !ismissing(metrics_row.repeat_determinism)
        push!(metrics_rows, Dict{String,Any}(
            "run_id" => m.run_id, "metric_name" => "repeat_determinism",
            "metric_value" => metrics_row.repeat_determinism, "metric_category" => "quality"))
    end

    metrics_df = isempty(metrics_rows) ? DataFrame(run_id=String[], metric_name=String[], metric_value=Any[], metric_category=String[]) : DataFrame(metrics_rows)

    warnings_rows = Dict{String,Any}[
        Dict{String,Any}("run_id" => m.run_id, "warning_category" => w.category,
         "warning_message" => w.message, "tensor_name" => _nothing_to_missing(w.tensor_name), "severity" => "info")
        for w in bundle.warnings
    ]
    warnings_df = DataFrame(warnings_rows)

    return runs_df, metrics_df, warnings_df
end

function normalize_bundles_dir(input_dir::AbstractString)::Tuple{DataFrame, DataFrame, DataFrame}
    runs_dfs = DataFrame[]
    metrics_dfs = DataFrame[]
    warnings_dfs = DataFrame[]

    if !isdir(input_dir)
        error("Input directory not found: $(input_dir)")
    end

    for (root, dirs, files) in walkdir(input_dir)
        if "run_manifest.json" in files
            bundle_path = root
            try
                bundle = load_saaq_bundle(bundle_path)
                runs_df, metrics_df, warnings_df = normalize_bundle_to_tables(bundle)
                push!(runs_dfs, runs_df)
                push!(metrics_dfs, metrics_df)
                push!(warnings_dfs, warnings_df)
            catch e
                @warn "Failed to load bundle at $(bundle_path): $(e)"
            end
        end
    end

    all_runs = isempty(runs_dfs) ? DataFrame(run_id=String[], run_status=String[]) : vcat(runs_dfs..., cols=:union)
    all_metrics = isempty(metrics_dfs) ? DataFrame(run_id=String[], metric_name=String[], metric_value=Any[], metric_category=String[]) : vcat(metrics_dfs..., cols=:union)
    all_warnings = isempty(warnings_dfs) ? DataFrame(run_id=String[], warning_category=String[], warning_message=String[], tensor_name=Union{String,Nothing}[], severity=String[]) : vcat(warnings_dfs..., cols=:union)

    return all_runs, all_metrics, all_warnings
end

export imported_latent_path, load_latent_df, detect_delta_column, maybe_entropy_column
export to_float64_vec, to_int_ms, summarise_run, pairwise_summary, fmt
export validate_path_component, IMPORT_ROOT
export RunStatus, RunManifest, RunMetrics, RunWarning, SaaqBundle
export real, synthetic, skipped, failed
export load_saaq_bundle, validate_saaq_bundle
export normalize_bundle_to_tables, normalize_bundles_dir

end # module Surrogate_Viz
