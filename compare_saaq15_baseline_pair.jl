using Pkg
Pkg.activate(@__DIR__)

using CSV
using DataFrames
import TOML
include(joinpath(@__DIR__, "src", "Surrogate_Viz.jl"))
using .Surrogate_Viz: imported_latent_path, load_latent_df, detect_delta_column,
    maybe_entropy_column, summarise_run, pairwise_summary, fmt

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")
ENV["QT_QPA_PLATFORM"] = get(ENV, "QT_QPA_PLATFORM", "offscreen")
using Plots

const REPO_ROOT = @__DIR__
const SELECTED_RUNS_PATH = joinpath(REPO_ROOT, "data", "selected_runs.toml")
const OUTPUT_DIR = joinpath(REPO_ROOT, "outputs", "olmoe-1b-7b", "dashboards")
const REPORT_PATH = joinpath(OUTPUT_DIR, "saaq15_re4_condition_comparison.md")
const PLOT_PATH = joinpath(OUTPUT_DIR, "saaq15_re4_condition_comparison.png")

function selected_repeat_idx()
    if !isempty(ARGS)
        return parse(Int, ARGS[1])
    end
    return parse(Int, get(ENV, "REPEAT_IDX", "0"))
end

function load_selected_runs(path::AbstractString)
    manifest = TOML.parsefile(path)
    runs = get(manifest, "runs", nothing)
    runs isa Vector || error("Expected [[runs]] entries in $(path)")
    return runs
end

function blessed_pair(runs::AbstractVector, repeat_idx::Int)
    blessed_runs = filter(runs) do run
        get(run, "blessed", false) == true &&
        get(run, "campaign", nothing) == "baseline_csv" &&
        run["model"] == "olmoe_baseline" &&
        run["family"] == "Olmoe" &&
        run["telemetry_source"] == "csv_re4_path_tracing_telemetry" &&
        run["rule"] == "SaaqV1_5SqrtRate" &&
        Int(run["repeat_idx"]) == repeat_idx
    end

    off_run = only(filter(run -> run["condition"] == "baseline", blessed_runs))
    on_run = only(filter(run -> run["condition"] == "treatment", blessed_runs))
    return off_run, on_run
end

function build_plot(off_df::DataFrame, on_df::DataFrame, joined_df::DataFrame, delta_col::Symbol, entropy_col::Union{Nothing,Symbol})
    default(fontfamily = "Helvetica", legend = :topright, lw = 2.5, size = (1400, entropy_col === nothing ? 900 : 1200), dpi = 180)

    p1 = plot(
        off_df.timestamp_ms,
        off_df[!, delta_col];
        label = "control-off",
        color = :navy,
        xlabel = "Timestamp (ms)",
        ylabel = string(delta_col),
        title = "SAAQ 1.5 Baseline Pair: $(delta_col)",
    )
    plot!(p1, on_df.timestamp_ms, on_df[!, delta_col]; label = "control-on", color = :crimson)

    p2 = plot(
        joined_df.timestamp_ms,
        joined_df.delta_on_minus_off;
        label = "control-on - control-off",
        color = :darkgreen,
        xlabel = "Timestamp (ms)",
        ylabel = "Delta Difference",
        title = "Pairwise Delta Difference",
    )
    hline!(p2, [0.0]; label = "zero", color = :black, linestyle = :dash)

    if entropy_col === nothing
        return plot(p1, p2; layout = (2, 1))
    end

    p3 = plot(
        off_df.timestamp_ms,
        off_df[!, entropy_col];
        label = "routing_entropy off",
        color = :purple4,
        xlabel = "Timestamp (ms)",
        ylabel = string(entropy_col),
        title = "Routing Entropy",
    )
    plot!(p3, on_df.timestamp_ms, on_df[!, entropy_col]; label = "routing_entropy on", color = :orange3)

    return plot(p1, p2, p3; layout = (3, 1))
end

function write_report(
    off_run::Dict{String,<:Any},
    on_run::Dict{String,<:Any},
    repeat_idx::Int,
    delta_col::Symbol,
    entropy_col::Union{Nothing,Symbol},
    run_summaries::Vector{Dict{String,Any}},
    pair_summary::Dict{String,Any},
)
    lines = String[]
    push!(lines, "# SAAQ 1.5 RE4 Paired-Run Comparison")
    push!(lines, "")
    push!(lines, "- Repeat index: `$(repeat_idx)`")
    push!(lines, "- Model: `$(off_run["model"])` (`$(off_run["family"])`)")
    push!(lines, "- Telemetry source: `$(off_run["telemetry_source"])`")
    push!(lines, "- Rule: `$(off_run["rule"])`")
    push!(lines, "- Delta column: `$(delta_col)`")
    push!(lines, "- Routing entropy column: `$(entropy_col === nothing ? "not present" : string(entropy_col))`")
    push!(lines, "- Plot: `$(relpath(PLOT_PATH, REPO_ROOT))`")
    push!(lines, "")
    push!(lines, "| Run | Condition | Rows | First ms | Last ms | Mean delta | Max delta | Final delta | Mean entropy | Final entropy |")
    push!(lines, "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

    for row in run_summaries
        push!(
            lines,
            "| `$(row["run_id"])` | `$(row["condition"])` | $(row["rows"]) | $(row["first_ms"]) | $(row["last_ms"]) | $(fmt(row["mean_delta"])) | $(fmt(row["max_delta"])) | $(fmt(row["final_delta"])) | $(fmt(row["mean_entropy"])) | $(fmt(row["final_entropy"])) |",
        )
    end

    push!(lines, "")
    push!(lines, "## Pairwise Summary")
    push!(lines, "")
    push!(lines, "| Metric | Value |")
    push!(lines, "| --- | ---: |")
    push!(lines, "| Paired rows | $(pair_summary["paired_rows"]) |")
    push!(lines, "| Mean delta (on - off) | $(fmt(pair_summary["mean_delta_on_minus_off"])) |")
    push!(lines, "| Max abs delta (on - off) | $(fmt(pair_summary["max_abs_delta_on_minus_off"])) |")
    push!(lines, "| Final delta (on - off) | $(fmt(pair_summary["final_delta_on_minus_off"])) |")
    if haskey(pair_summary, "mean_entropy_on_minus_off")
        push!(lines, "| Mean entropy (on - off) | $(fmt(pair_summary["mean_entropy_on_minus_off"])) |")
        push!(lines, "| Final entropy (on - off) | $(fmt(pair_summary["final_entropy_on_minus_off"])) |")
    end

    push!(lines, "")
    push!(lines, "## Imported Inputs")
    push!(lines, "")
    push!(lines, "- `$(relpath(imported_latent_path(off_run), REPO_ROOT))`")
    push!(lines, "- `$(relpath(imported_latent_path(on_run), REPO_ROOT))`")

    open(REPORT_PATH, "w") do io
        write(io, join(lines, "\n"))
        write(io, "\n")
    end
end

function main()
    repeat_idx = selected_repeat_idx()
    runs = load_selected_runs(SELECTED_RUNS_PATH)
    off_run, on_run = blessed_pair(runs, repeat_idx)

    off_df = load_latent_df(off_run)
    on_df = load_latent_df(on_run)

    delta_col = detect_delta_column([off_df, on_df])
    entropy_col = maybe_entropy_column([off_df, on_df])

    run_summaries = [
        summarise_run(off_df, off_run, delta_col, entropy_col),
        summarise_run(on_df, on_run, delta_col, entropy_col),
    ]
    joined_df, pair_summary = pairwise_summary(off_df, on_df, delta_col, entropy_col)

    mkpath(OUTPUT_DIR)
    fig = build_plot(off_df, on_df, joined_df, delta_col, entropy_col)
    savefig(fig, PLOT_PATH)
    write_report(off_run, on_run, repeat_idx, delta_col, entropy_col, run_summaries, pair_summary)

    println("Compared blessed OLMoE baseline runs for repeat $(repeat_idx)")
    println("Loaded control-off from $(imported_latent_path(off_run))")
    println("Loaded control-on from $(imported_latent_path(on_run))")
    println("Saved plot to $(PLOT_PATH)")
    println("Saved markdown report to $(REPORT_PATH)")
end

main()
