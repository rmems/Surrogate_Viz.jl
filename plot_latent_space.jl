using Pkg
Pkg.activate(@__DIR__)

using CSV
using DataFrames
ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")
ENV["QT_QPA_PLATFORM"] = get(ENV, "QT_QPA_PLATFORM", "offscreen")
using Plots

# Grok Build 0.1 model (Linear RM-62 / GH#43): CUDA-aware visual helpers.
# Density, path raster, and spike overlay use CUDABackend when CUDA is
# functional; otherwise the CPU kernels in src/kernels.jl. The implementation
# lives in ext/CUDABackendExt.jl (package extension), not a src/cuda_backend.jl.
import Surrogate_Viz as SV

# Accept the original first-exp line (`tick=1 best_walker=627 elapsed_us=...`)
# and later corinth tick rows that append gpu/cpu fields. No heartbeat fields.
const TICK_PATTERN = r"^tick=(\d+)\s+best_walker=(\d+)"

# Grok Build 0.1 model: defaults to the first OLMoE math/logic tick file.
function input_path()
    if length(ARGS) >= 1
        return ARGS[1]
    end
    return "data/math_logic_tick_telemetry.txt"
end

function output_path()
    if length(ARGS) >= 2
        return ARGS[2]
    end
    return "map_olmoe_math_logic.png"
end

function latent_path()
    return length(ARGS) >= 3 ? ARGS[3] : nothing
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

function load_firing_weights(path::Union{Nothing,AbstractString}, n_ticks::Int)
    path === nothing && return nothing
    isfile(path) || error("Latent telemetry not found at $(path)")
    df = CSV.read(path, DataFrame)
    hasproperty(df, :avg_pop_firing_rate_hz) ||
        error("Missing avg_pop_firing_rate_hz in $(path)")

    vals = Vector{Float64}(undef, nrow(df))
    @inbounds for i in 1:nrow(df)
        v = df[i, :avg_pop_firing_rate_hz]
        vals[i] = SV.is_finite_visual(v) ? Float64(v) : NaN
    end
    if length(vals) != n_ticks
        @warn "Latent firing length $(length(vals)) does not match tick rows $(n_ticks); using occupancy (walker-as-spike) overlay instead of firing rates" path = path
        return nothing
    end
    return vals
end

function bin_centers(edges::AbstractVector)
    return (edges[1:(end - 1)] .+ edges[2:end]) ./ 2
end

function visual_backend(use_cuda::Bool)
    return (use_cuda && SV.has_cuda()) ? SV.CUDABackend() : SV.CPUBackend()
end

# Grok Build 0.1 model: path raster + firing density + spiking overlay.
# CUDABackend is used for the 2-D rasters and the 1-D density histogram when
# a GPU is available. Non-finite firing (NaN/Inf) is dropped from the overlay
# mean so the PNG never shows NaN holes; quiet 0-Hz ticks stay as zeros.
function build_dashboard(df::DataFrame; firing=nothing, use_cuda::Bool=true)
    default(fontfamily="Helvetica", legend=false, size=(1400, 1200), dpi=180)

    backend = visual_backend(use_cuda)
    gpu_label = backend isa SV.CUDABackend ? " (CUDA)" : ""

    ticks = df[!, :tick]
    walkers = Int.(df[!, :best_walker])

    raster = SV.prepare_path_raster(
        ticks, walkers, backend;
        n_tick_bins=256, n_walker_bins=128, max_walker=2047,
    )
    overlay = if firing === nothing
        SV.prepare_spike_overlay(
            ticks, walkers, backend;
            n_tick_bins=256, n_walker_bins=128, max_walker=2047,
        )
    else
        SV.prepare_spike_overlay(
            ticks, walkers, firing, backend;
            n_tick_bins=256, n_walker_bins=128, max_walker=2047,
        )
    end

    tick_c = bin_centers(raster.tick_edges)
    walker_c = bin_centers(raster.walker_edges)

    p1 = heatmap(
        tick_c,
        walker_c,
        raster.counts;
        title="SNN Routing Path Over Time$(gpu_label)",
        xlabel=SV.pretty_column("tick"),
        ylabel=SV.pretty_column("best_walker"),
        # GR heatmaps cannot use ylims=(2047, 0) (GKS memory error). yflip
        # keeps the original first-exp orientation: high walker indices at top.
        yflip=true,
        ylims=(0, 2047),
        color=:hot,
        colorbar=true,
        legend=false,
    )
    scatter!(
        p1,
        ticks,
        walkers;
        markersize=2.5,
        color=:deepskyblue,
        markeralpha=0.55,
        markerstrokewidth=0,
        legend=false,
    )

    edges, counts = SV.walker_density_bins_and_counts(walkers; n_bins=32, max_walker=2047)
    p2 = bar(
        edges[1:(end - 1)],
        counts;
        title="Best Walker Firing Density$(gpu_label)",
        xlabel=SV.pretty_column("best_walker"),
        ylabel="Count",
        xlims=(0, 2047),
        color=:tomato,
        alpha=0.8,
        linecolor=:black,
        linewidth=1.0,
        legend=false,
    )

    overlay_c = bin_centers(overlay.tick_edges)
    overlay_w = bin_centers(overlay.walker_edges)
    overlay_title = firing === nothing ?
        "Spiking Overlay (walker visits)$(gpu_label)" :
        "Spiking Overlay (population firing)$(gpu_label)"
    p3 = heatmap(
        overlay_c,
        overlay_w,
        overlay.intensity;
        title=overlay_title,
        xlabel=SV.pretty_column("tick"),
        ylabel=SV.pretty_column("best_walker"),
        yflip=true,
        ylims=(0, 2047),
        color=:inferno,
        colorbar=true,
        clims=(0, max(maximum(overlay.intensity), eps(Float64))),
        legend=false,
    )

    return plot(p1, p2, p3; layout=(3, 1), size=(1400, 1200), dpi=180)
end

function main()
    input_file = input_path()
    output_file = output_path()
    firing_file = latent_path()

    df = load_tick_data(input_file)
    firing = load_firing_weights(firing_file, nrow(df))
    fig = build_dashboard(df; firing=firing)
    savefig(fig, output_file)

    println("Loaded $(nrow(df)) tick rows from $(input_file)")
    if firing !== nothing
        println("Joined $(length(firing)) firing-rate rows from $(firing_file)")
    end
    println("Saved dashboard to $(output_file)")
    println("Grok Build 0.1 model: path raster + walker density + spike overlay (CUDA when available). No heartbeat.")
end

# Guard so that `include("plot_latent_space.jl")` (e.g. from CI -e blocks) does not auto-execute the CLI.
# Direct `julia plot_latent_space.jl [input] [output] [latent]` still runs as before.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
