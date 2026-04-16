using DataFrames
using CairoMakie

const INPUT_PATH = joinpath(@__DIR__, "smoke_test_output.txt")
const OUTPUT_PATH = joinpath(@__DIR__, "latent_space_exploration.png")
const TICK_PATTERN = r"^tick=(\d+) best_walker=(\d+) elapsed_us=\d+$"

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

    return DataFrame(tick = ticks, best_walker = best_walkers)
end

function build_dashboard(df::DataFrame)
    fig = Figure(size = (1400, 900), fontsize = 18)

    ax_path = Axis(
        fig[1, 1],
        title = "SNN Routing Path Over Time",
        xlabel = "Tick",
        ylabel = "Best Walker Index",
    )

    scatter!(
        ax_path,
        df.tick,
        df.best_walker;
        markersize = 16,
        color = :dodgerblue3,
        strokewidth = 0.75,
        strokecolor = :black,
    )
    ylims!(ax_path, 0, 2047)

    ax_hist = Axis(
        fig[2, 1],
        title = "Best Walker Firing Density",
        xlabel = "Best Walker Index",
        ylabel = "Count",
    )

    hist!(
        ax_hist,
        df.best_walker;
        bins = 0:64:2048,
        color = (:tomato, 0.8),
        strokecolor = :black,
        strokewidth = 1.0,
    )
    xlims!(ax_hist, 0, 2047)

    return fig
end

function main()
    df = load_tick_data(INPUT_PATH)
    fig = build_dashboard(df)
    save(OUTPUT_PATH, fig; px_per_unit = 3)

    println("Loaded $(nrow(df)) tick rows from $(INPUT_PATH)")
    println("Saved dashboard to $(OUTPUT_PATH)")
end

main()
