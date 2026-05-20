using CSV
using DataFrames
ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")
ENV["QT_QPA_PLATFORM"] = get(ENV, "QT_QPA_PLATFORM", "offscreen")
using Dates
using Plots
using Statistics
using TOML

const REPO_ROOT = @__DIR__
const SELECTED_RUNS_PATH = joinpath(REPO_ROOT, "data", "selected_runs.toml")
const IMPORT_ROOT = joinpath(REPO_ROOT, "data", "corinth_runs")
const OUTPUT_DIR = joinpath(REPO_ROOT, "outputs", "full_lineup")
const REPORT_PATH = joinpath(OUTPUT_DIR, "full_lineup_saaq15_comparison.md")

const CAMPAIGN = "full_lineup"
const TELEMETRY_SOURCE = "csv_re4_path_tracing_telemetry"
const RULE = "SaaqV1_5SqrtRate"
const REPEAT_IDX = 0

const MODEL_ORDER = [
    "olmoe_baseline",
    "qwen3_moe_i1_iq3_m",
    "gemma4_26b_a4b_iq4_nl",
    "deepseek_coder_v2_lite_q6_k_l",
    "llama_3_2_dark_champion_q5_k_m",
    # Onboarded in corinth-canal LLM-models-onboarding PR #68
    "zaya1_8b_q8_0",
    "glm46v_flash_q8_0",
    "kimi_vl_a3b_q6_k",
    "marco_nano_base_q8_0",
]

function load_selected_runs(path::AbstractString)
    manifest = TOML.parsefile(path)
    runs = get(manifest, "runs", nothing)
    runs isa Vector || error("Expected [[runs]] entries in $(path)")
    return runs
end

function full_lineup_runs(all_runs::AbstractVector)
    return filter(all_runs) do run
        get(run, "campaign", nothing) == CAMPAIGN &&
        run["telemetry_source"] == TELEMETRY_SOURCE &&
        run["rule"] == RULE &&
        Int(run["repeat_idx"]) == REPEAT_IDX &&
        get(run, "blessed", false) == true
    end
end

function model_pair(runs::AbstractVector, model_slug::AbstractString)
    model_runs = filter(run -> run["model"] == model_slug, runs)
    off_run = only(filter(run -> run["heartbeat"] == "heartbeat_off", model_runs))
    on_run = only(filter(run -> run["heartbeat"] == "heartbeat_on", model_runs))
    return off_run, on_run
end

function validate_pairs(runs::AbstractVector, models::AbstractVector{<:AbstractString})
    available = String[]
    problems = String[]
    for slug in models
        off_matches = filter(run -> run["model"] == slug && run["heartbeat"] == "heartbeat_off", runs)
        on_matches = filter(run -> run["model"] == slug && run["heartbeat"] == "heartbeat_on", runs)
        if length(off_matches) == 0 || length(on_matches) == 0
            push!(problems, "missing run: model=$(slug) (off=$(length(off_matches)), on=$(length(on_matches)))")
        else
            if length(off_matches) > 1
                ids = join((m["id"] for m in off_matches), ", ")
                push!(problems, "duplicate heartbeat_off runs: model=$(slug) ids=[$(ids)]")
            end
            if length(on_matches) > 1
                ids = join((m["id"] for m in on_matches), ", ")
                push!(problems, "duplicate heartbeat_on runs: model=$(slug) ids=[$(ids)]")
            end
            if length(off_matches) == 1 && length(on_matches) == 1
                push!(available, slug)
            end
        end
    end

    for p in problems
        @warn "Model validation: $p"
    end

    if isempty(available)
        error(
            "compare_full_lineup_saaq15.jl: no models with complete (off+on) runs found. " *
            "Filter: campaign=$(CAMPAIGN), repeat_idx=$(REPEAT_IDX), " *
            "telemetry_source=$(TELEMETRY_SOURCE), rule=$(RULE). " *
            "Run `import_corinth_runs.jl` first.",
        )
    end

    return available
end

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
        "mean_delta" => mean(delta_values),
        "max_delta" => maximum(delta_values),
        "final_delta" => last(delta_values),
    )

    if entropy_col !== nothing
        entropy_values = to_float64_vec(df[!, entropy_col])
        if isempty(entropy_values)
            row["mean_entropy"] = missing
            row["final_entropy"] = missing
        else
            row["mean_entropy"] = mean(entropy_values)
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
        "mean_delta_on_minus_off" => mean(joined.delta_on_minus_off),
        "max_abs_delta_on_minus_off" => maximum(abs.(joined.delta_on_minus_off)),
        "final_delta_on_minus_off" => last(joined.delta_on_minus_off),
    )

    if entropy_col !== nothing
        joined.entropy_on_minus_off = joined.entropy_on .- joined.entropy_off
        summary["mean_entropy_on_minus_off"] = mean(joined.entropy_on_minus_off)
        summary["final_entropy_on_minus_off"] = last(joined.entropy_on_minus_off)
    end

    return joined, summary
end

function build_plot(model_slug::AbstractString, off_df::DataFrame, on_df::DataFrame, joined_df::DataFrame, delta_col::Symbol, entropy_col::Union{Nothing,Symbol})
    panel_attrs = (fontfamily = "Helvetica", legend = :topright, lw = 2.0)
    fig_size = (1400, entropy_col === nothing ? 900 : 1200)

    p1 = plot(
        off_df.timestamp_ms,
        off_df[!, delta_col];
        label = "heartbeat_off",
        color = :navy,
        xlabel = "Timestamp (ms)",
        ylabel = string(delta_col),
        title = "$(model_slug) — SAAQ 1.5 $(delta_col)",
        panel_attrs...,
    )
    plot!(p1, on_df.timestamp_ms, on_df[!, delta_col]; label = "heartbeat_on", color = :crimson)

    p2 = plot(
        joined_df.timestamp_ms,
        joined_df.delta_on_minus_off;
        label = "heartbeat_on - heartbeat_off",
        color = :darkgreen,
        xlabel = "Timestamp (ms)",
        ylabel = "Delta Difference",
        title = "Pairwise Delta Difference",
        panel_attrs...,
    )
    hline!(p2, [0.0]; label = "zero", color = :black, linestyle = :dash)

    if entropy_col === nothing
        return plot(p1, p2; layout = (2, 1), size = fig_size, dpi = 180)
    end

    p3 = plot(
        off_df.timestamp_ms,
        off_df[!, entropy_col];
        label = "routing_entropy off",
        color = :purple4,
        xlabel = "Timestamp (ms)",
        ylabel = string(entropy_col),
        title = "Routing Entropy",
        panel_attrs...,
    )
    plot!(p3, on_df.timestamp_ms, on_df[!, entropy_col]; label = "routing_entropy on", color = :orange3)

    return plot(p1, p2, p3; layout = (3, 1), size = fig_size, dpi = 180)
end

fmt(x::Missing) = "-"
function fmt(x::Real)
    rounded = round(Float64(x); digits = 6)
    rounded == 0.0 && (rounded = 0.0)  # normalize -0.0 -> 0.0
    return string(rounded)
end
fmt(x) = string(x)

struct ModelResult
    slug::String
    family::String
    off_run::Dict{String,Any}
    on_run::Dict{String,Any}
    delta_col::Symbol
    entropy_col::Union{Nothing,Symbol}
    run_summaries::Vector{Dict{String,Any}}
    pair_summary::Dict{String,Any}
    plot_path::String
end

function process_model(runs::AbstractVector, model_slug::AbstractString)
    off_run, on_run = model_pair(runs, model_slug)
    family = String(get(off_run, "family", ""))

    off_df = load_latent_df(off_run)
    on_df = load_latent_df(on_run)

    delta_col = detect_delta_column([off_df, on_df])
    entropy_col = maybe_entropy_column([off_df, on_df])

    run_summaries = [
        summarise_run(off_df, off_run, delta_col, entropy_col),
        summarise_run(on_df, on_run, delta_col, entropy_col),
    ]
    joined_df, pair_summary = pairwise_summary(off_df, on_df, delta_col, entropy_col)

    plot_path = joinpath(OUTPUT_DIR, "$(model_slug).png")
    fig = build_plot(model_slug, off_df, on_df, joined_df, delta_col, entropy_col)
    savefig(fig, plot_path)

    return ModelResult(
        String(model_slug),
        family,
        Dict{String,Any}(off_run),
        Dict{String,Any}(on_run),
        delta_col,
        entropy_col,
        run_summaries,
        pair_summary,
        plot_path,
    )
end

function append_model_section!(lines::Vector{String}, result::ModelResult)
    push!(lines, "## $(result.slug) ($(result.family))")
    push!(lines, "")
    push!(lines, "- heartbeat_off run: `$(result.off_run["id"])`")
    push!(lines, "- heartbeat_on  run: `$(result.on_run["id"])`")
    push!(lines, "- imported off:    `$(relpath(imported_latent_path(result.off_run), REPO_ROOT))`")
    push!(lines, "- imported on:     `$(relpath(imported_latent_path(result.on_run), REPO_ROOT))`")
    push!(lines, "- delta column:    `$(result.delta_col)`")
    push!(lines, "- routing entropy: `$(result.entropy_col === nothing ? "not present" : string(result.entropy_col))`")
    push!(lines, "")
    push!(lines, "| Heartbeat | Rows | First ms | Last ms | Mean delta | Max delta | Final delta | Mean entropy | Final entropy |")
    push!(lines, "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in result.run_summaries
        push!(
            lines,
            "| `$(row["heartbeat"])` | $(row["rows"]) | $(row["first_ms"]) | $(row["last_ms"]) | $(fmt(row["mean_delta"])) | $(fmt(row["max_delta"])) | $(fmt(row["final_delta"])) | $(fmt(row["mean_entropy"])) | $(fmt(row["final_entropy"])) |",
        )
    end
    push!(lines, "")
    push!(lines, "**Pairwise summary**")
    push!(lines, "")
    push!(lines, "| Metric | Value |")
    push!(lines, "| --- | ---: |")
    push!(lines, "| Paired rows | $(result.pair_summary["paired_rows"]) |")
    push!(lines, "| Mean delta (on - off) | $(fmt(result.pair_summary["mean_delta_on_minus_off"])) |")
    push!(lines, "| Max abs delta (on - off) | $(fmt(result.pair_summary["max_abs_delta_on_minus_off"])) |")
    push!(lines, "| Final delta (on - off) | $(fmt(result.pair_summary["final_delta_on_minus_off"])) |")
    if haskey(result.pair_summary, "mean_entropy_on_minus_off")
        push!(lines, "| Mean entropy (on - off) | $(fmt(result.pair_summary["mean_entropy_on_minus_off"])) |")
        push!(lines, "| Final entropy (on - off) | $(fmt(result.pair_summary["final_entropy_on_minus_off"])) |")
    end
    push!(lines, "")
    push!(lines, "![$(result.slug)]($(basename(result.plot_path)))")
    push!(lines, "")
end

function append_cheat_sheet!(lines::Vector{String}, results::Vector{ModelResult})
    push!(lines, "## Cross-Model Delta Cheat Sheet")
    push!(lines, "")
    push!(lines, "| Model | Family | Mean delta (on - off) | Max abs delta (on - off) | Final delta (on - off) |")
    push!(lines, "| --- | --- | ---: | ---: | ---: |")
    for r in results
        ps = r.pair_summary
        push!(
            lines,
            "| `$(r.slug)` | `$(r.family)` | $(fmt(ps["mean_delta_on_minus_off"])) | $(fmt(ps["max_abs_delta_on_minus_off"])) | $(fmt(ps["final_delta_on_minus_off"])) |",
        )
    end
    push!(lines, "")
end

function write_report(results::Vector{ModelResult})
    lines = String[]
    push!(lines, "# Full Lineup SAAQ 1.5 Heartbeat Comparison")
    push!(lines, "")
    push!(lines, "- Campaign: `$(CAMPAIGN)`")
    push!(lines, "- Repeat index: `$(REPEAT_IDX)`")
    push!(lines, "- Telemetry source: `$(TELEMETRY_SOURCE)`")
    push!(lines, "- Rule: `$(RULE)`")
    push!(lines, "- Models: $(length(results)) ($(join((r.slug for r in results), ", ")))")
    push!(lines, "- Generated: `$(Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"))`")
    push!(lines, "")

    for r in results
        append_model_section!(lines, r)
    end
    append_cheat_sheet!(lines, results)

    open(REPORT_PATH, "w") do io
        write(io, join(lines, "\n"))
        write(io, "\n")
    end
end

function main()
    runs = load_selected_runs(SELECTED_RUNS_PATH)
    campaign_runs = full_lineup_runs(runs)
    isempty(campaign_runs) && error("No runs found for campaign=$(CAMPAIGN), repeat_idx=$(REPEAT_IDX) in $(SELECTED_RUNS_PATH)")
    available = validate_pairs(campaign_runs, MODEL_ORDER)

    mkpath(OUTPUT_DIR)
    results = ModelResult[]
    for slug in available
        push!(results, process_model(campaign_runs, slug))
    end

    write_report(results)

    println("Compared $(length(results)) full_lineup models for repeat $(REPEAT_IDX)")
    for r in results
        println("  $(r.slug): plot=$(relpath(r.plot_path, REPO_ROOT))")
    end
    println("Saved markdown report to $(REPORT_PATH)")
end

main()
