using Pkg
Pkg.activate(@__DIR__)

using DataFrames
ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")
ENV["QT_QPA_PLATFORM"] = get(ENV, "QT_QPA_PLATFORM", "offscreen")
using Plots

# Grok Build 0.1 model: bring in the CUDA-aware visual helpers (and has_cuda).
# If CUDA is installed and functional in the active environment, the density
# panel will use the GPU-backed histogram path; otherwise it falls back to CPU.
const SV = Base.require(Base.PkgId(Base.UUID("0e7d9c34-7da8-46ec-ad35-4cb1b8ff7bae"), "Surrogate_Viz"))

# Grok Build 0.1 model: accepts input paths for telemetry; defaults to generic data file.
# No og data directories are used (per user request). Use pure-Julia CUDA (see kernels)
# for improved visual "looks" on the density/path panels (combined #43/#44 work in one PR).

const TICK_PATTERN = r"^tick=(\d+) best_walker=(\d+) elapsed_us=\d+$"

# Support the original naming (telemetry_olmoe_math_logic.txt -> map_olmoe_math_logic.png)
# as well as corinth paths. No og data directories.
function input_path()
    if length(ARGS) >= 1
        return ARGS[1]
    end
    # Grok Build 0.1 model: default to non-og data file. Provide via args if needed.
    return "data/math_logic_tick_telemetry.txt"
end

function output_path()
    if length(ARGS) >= 2
        return ARGS[2]
    end
    return "map_olmoe_math_logic.png"
end

function load_tick_data(path::AbstractString)
    ticks = Int[]
    best_walkers = Int[]

    for line in eachline(path)
        match_result = match(TICK_PATTERN, line)
        match_result === nothing && continue

        push!(ticks, parse(Int, match_result.captures[1]))
        push!(best_walkers, parse(Int, match_result.captures[2]))
    end

    isempty(ticks) && error("No tick data found in $(path). Expected lines like 'tick=1 best_walker=1976 elapsed_us=2584'.")

    return DataFrame(tick=ticks, best_walker=best_walkers)
end

# Grok Build 0.1 model: optional pure-Julia CUDA path for the "Best Walker Firing Density" histogram.
# The CUDA-backed implementation is routed through Surrogate_Viz and lives in
# src/cuda_backend.jl, with CPU fallback when CUDA is unavailable or disabled.
function build_dashboard(df::DataFrame; use_cuda::Bool=true)
    default(fontfamily="Helvetica", legend=false, size=(1400, 900), dpi=180)

    p1 = scatter(
        df[!, :tick],
        df[!, :best_walker];
        title="SNN Routing Path Over Time",
        xlabel=SV.pretty_column("tick"),
        ylabel=SV.pretty_column("best_walker"),
        # Grok Build 0.1 model: ylims=(2047, 0) for reversed y-axis (higher walker indices at top)
        # to match historical walker/spiking graph orientation.
        ylims=(2047, 0),
        markersize=6,
        color=:dodgerblue3,
        markeralpha=0.85,
        markerstrokewidth=0.75,
        markerstrokecolor=:black,
        legend=false,
    )

    # Density panel — use the Surrogate_Viz API for CUDA or CPU fallback (Grok Build 0.1 model).
    # This ensures the CUDA kernel is actually used when available (fixed per review).
    p2 = if use_cuda && SV.has_cuda() && !isempty(methods(SV.cuda_best_walker_density_histogram))
        edges, counts = SV.walker_density_bins_and_counts(df[!, :best_walker]; n_bins=32, max_walker=2047)
        bar(
            edges[1:end-1],
            counts;
            title="Best Walker Firing Density (CUDA path)",
            xlabel=SV.pretty_column("best_walker"),
            ylabel="Count",
            xlims=(0, 2047),
            color=:tomato,
            alpha=0.8,
            linecolor=:black,
            linewidth=1.0,
            legend=false,
        )
    else
        histogram(
            df[!, :best_walker];
            title="Best Walker Firing Density",
            xlabel=SV.pretty_column("best_walker"),
            ylabel="Count",
            bins=0:64:2048,
            xlims=(0, 2047),
            color=:tomato,
            alpha=0.8,
            linecolor=:black,
            linewidth=1.0,
            legend=false,
        )
    end

    return plot(p1, p2; layout=(2, 1), size=(1400, 900), dpi=180)
end

function main()
    input_file = input_path()
    output_file = output_path()

    df = load_tick_data(input_file)
    fig = build_dashboard(df)
    savefig(fig, output_file)

    println("Loaded $(nrow(df)) tick rows from $(input_file)")
    println("Saved dashboard to $(output_file)")
    println("Grok Build 0.1 model: pure Julia CUDA visual kernels used for density when available. No og data directories.")
end

# Guard so that `include("plot_latent_space.jl")` (e.g. from CI -e blocks) does not auto-execute the CLI.
# Direct `julia plot_latent_space.jl [input] [output]` still runs as before.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
