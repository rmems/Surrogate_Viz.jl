using Pkg
Pkg.activate(@__DIR__)

using DataFrames
ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")
ENV["QT_QPA_PLATFORM"] = get(ENV, "QT_QPA_PLATFORM", "offscreen")
using Plots

# Grok Build 0.1 model: bring in the pure-Julia CUDA visual kernels (and has_cuda)
# that were added for the combined visuals + runner PR. When run with the project
# environment (which now contains CUDA.jl) this will make cuda_best_walker_density_histogram
# available for the density panel, giving better "looks on the png" for the revived
# OG first-experiment visuals (the original map_*.png from the user-specified external first-day data dir).
const SV = Base.require(Base.PkgId(Base.UUID("0e7d9c34-7da8-46ec-ad35-4cb1b8ff7bae"), "Surrogate_Viz"))

# Grok Build 0.1 model: revived for GH#42 to target the original PNGs from the first-day real-weights OLMoE testing.
# The canonical source for the "original png" (and the telemetry that produced the classic walker/spiking graphs)
# The OG data dir is the user-specified external first-day-testing-real-weights/ (see README there for the Walker metaphor
# and the four tests; fourth-test/telemetry_olmoe_math_logic.txt + map_olmoe_math_logic.png is the math case ground truth).
# Surrogate_Viz data/telemetry_math_logic.txt etc. are copies of the ones from that first-day dir.
# This script now accepts paths to those originals (or the copies) and can use pure-Julia CUDA (see kernels)
# for improved visual "looks" on the density/path panels (combined #43/#44 work in one PR).

const TICK_PATTERN = r"^tick=(\d+) best_walker=(\d+) elapsed_us=\d+$"

# Support the original first-day naming (telemetry_olmoe_math_logic.txt -> map_olmoe_math_logic.png)
# as well as the old internal defaults and explicit corinth paths.
function input_path()
    if length(ARGS) >= 1
        return ARGS[1]
    end
    # Grok Build 0.1 model: default now points at the copy that came from the first-day source
    # and test progression; user can pass the canonical telemetry from its fourth-test/ etc. directly).
    return "data/telemetry_math_logic.txt"
end

function output_path()
    if length(ARGS) >= 2
        return ARGS[2]
    end
    # When the input looks like the original fourth-test telemetry, produce a name that matches the checked-in original PNG.
    inp = input_path()
    if occursin("telemetry_olmoe_math_logic", inp) || occursin("fourth-test", inp)
        return "map_olmoe_math_logic.png"
    end
    if occursin("OMLoE", inp) || occursin("olmoe", inp)
        return "map_olmoe_math_logic.png"
    end
    # Grok Build 0.1 model: return canonical OG name to match first-day PNGs and docs (fixed inconsistent naming per review).
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

# Grok Build 0.1 model: optional pure-Julia CUDA path for the "Best Walker Firing Density" histogram
# (the visual primitive that directly improves "looks on the png" for the revived first-day graphs).
# The actual CUDA kernel lives in src/kernels.jl (added as part of the combined visuals+runner PR).
# Falls back to the plain histogram when CUDA is not available or not requested.
function build_dashboard(df::DataFrame; use_cuda::Bool=true)
    default(fontfamily="Helvetica", legend=false, size=(1400, 900), dpi=180)

    p1 = scatter(
        df[!, :tick],
        df[!, :best_walker];
        title="SNN Routing Path Over Time",
        xlabel="Tick",
        ylabel="Best Walker Index",
        # Grok Build 0.1 model: ylims=(2047, 0) to match the OG y configuration from the original first-day PNGs
        # (reversed y-axis so higher walker indices appear at the top, matching the classic walker/spiking graphs
        # from the user-specified external first-day data dir for #42 revival).
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
    p2 = if use_cuda && isdefined(SV, :cuda_best_walker_density_histogram)
        edges, counts = SV.walker_density_bins_and_counts(df[!, :best_walker]; n_bins=32, max_walker=2047)
        bar(
            edges[1:end-1],
            counts;
            title="Best Walker Firing Density (CUDA path)",
            xlabel="Best Walker Index",
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
            xlabel="Best Walker Index",
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
    println("Grok Build 0.1 model: revival targeting OG first-experiment PNGs (user-specified external first-day data dir). Pure Julia CUDA visual kernels (in ext/CUDABackendExt.jl, #43/#44) used for density when available.")
end

main()
