using DataFrames
using CairoMakie

const TICK_PATTERN = r"^tick=(\d+) best_walker=(\d+) elapsed_us=\d+$"

input_path() = get(ARGS, 1, "telemetry_OMLoE_math_logic.txt")
output_path() = get(ARGS, 2, "map__OMLoE_math_logic.png")

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

function build_dashboard(df::DataFrame)
    default(fontfamily="Helvetica", legend=false, size=(1400, 900), dpi=180)

    p1 = scatter(
        df.tick,
        df.best_walker;
        title="SNN Routing Path Over Time",
        xlabel="Tick",
        ylabel="Best Walker Index",
        ylims=(0, 2047),
        markersize=6,
        color=:dodgerblue3,
        markeralpha=0.85,
        markerstrokewidth=0.75,
        markerstrokecolor=:black,
        legend=false,
    )

    p2 = histogram(
        df.best_walker;
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
end

main()
