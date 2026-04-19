using CSV
using DataFrames
using Plots

const TICK_PATTERN = r"^tick=(\d+) best_walker=(\d+) elapsed_us=(\d+) heartbeat_signal=([-+0-9.eE]+) gpu_temp_c=([-+0-9.eE]+) gpu_power_w=([-+0-9.eE]+) cpu_tctl_c=([-+0-9.eE]+) cpu_package_power_w=([-+0-9.eE]+)$"

latent_input_path() = get(ARGS, 1, "latent_telemetry.csv")
tick_input_path() = get(ARGS, 2, "tick_telemetry.txt")
output_path() = get(ARGS, 3, "saaq15_validation_dashboard.png")

function load_latent_data(path::AbstractString)
    df = CSV.read(path, DataFrame)
    required = [
        :timestamp_ms,
        :avg_pop_firing_rate_hz,
        :routing_entropy,
        :heartbeat_signal,
        :heartbeat_enabled,
        :gpu_temp_c,
        :gpu_power_w,
        :cpu_tctl_c,
        :cpu_package_power_w,
    ]
    missing = setdiff(required, Symbol.(names(df)))
    isempty(missing) || error("Missing required latent columns in $(path): $(join(string.(missing), ", "))")
    nrow(df) > 0 || error("No latent rows found in $(path)")

    df.tick = Int.(round.(df.timestamp_ms))
    sort!(df, :tick)
    return df
end

function load_tick_data(path::AbstractString)
    ticks = Int[]
    best_walkers = Int[]
    elapsed_us = Int[]
    heartbeat_signal = Float64[]
    gpu_temp_c = Float64[]
    gpu_power_w = Float64[]
    cpu_tctl_c = Float64[]
    cpu_package_power_w = Float64[]

    for line in eachline(path)
        match_result = match(TICK_PATTERN, line)
        match_result === nothing && continue

        push!(ticks, parse(Int, match_result.captures[1]))
        push!(best_walkers, parse(Int, match_result.captures[2]))
        push!(elapsed_us, parse(Int, match_result.captures[3]))
        push!(heartbeat_signal, parse(Float64, match_result.captures[4]))
        push!(gpu_temp_c, parse(Float64, match_result.captures[5]))
        push!(gpu_power_w, parse(Float64, match_result.captures[6]))
        push!(cpu_tctl_c, parse(Float64, match_result.captures[7]))
        push!(cpu_package_power_w, parse(Float64, match_result.captures[8]))
    end

    isempty(ticks) && error("No tick data found in $(path). Expected heartbeat-aware telemetry lines.")

    return DataFrame(
        tick = ticks,
        best_walker = best_walkers,
        elapsed_us = elapsed_us,
        heartbeat_signal = heartbeat_signal,
        gpu_temp_c = gpu_temp_c,
        gpu_power_w = gpu_power_w,
        cpu_tctl_c = cpu_tctl_c,
        cpu_package_power_w = cpu_package_power_w,
    )
end

function scaled_overlay(signal, target)
    length(signal) == length(target) || error("Overlay length mismatch")
    isempty(signal) && return Float64[]

    signal_values = Float64.(signal)
    target_values = Float64.(target)

    signal_lo = minimum(signal_values)
    signal_hi = maximum(signal_values)
    target_lo = minimum(target_values)
    target_hi = maximum(target_values)

    if signal_hi - signal_lo < 1e-9
        fill((target_lo + target_hi) / 2, length(signal_values))
    elseif target_hi - target_lo < 1e-9
        fill(target_lo, length(signal_values))
    else
        target_lo .+ ((signal_values .- signal_lo) ./ (signal_hi - signal_lo)) .* (target_hi - target_lo)
    end
end

function build_dashboard(latent_df::DataFrame, tick_df::DataFrame)
    default(fontfamily = "Helvetica", legend = :topright, lw = 2, size = (1500, 1200), dpi = 180)

    rate_overlay = scaled_overlay(latent_df.heartbeat_signal, latent_df.avg_pop_firing_rate_hz)
    entropy_overlay = scaled_overlay(latent_df.heartbeat_signal, latent_df.routing_entropy)
    walker_overlay = scaled_overlay(tick_df.heartbeat_signal, tick_df.best_walker)
    power_overlay = scaled_overlay(latent_df.heartbeat_signal, latent_df.gpu_power_w)

    p1 = plot(
        latent_df.tick,
        latent_df.avg_pop_firing_rate_hz;
        label = "avg_pop_firing_rate_hz",
        color = :navy,
        xlabel = "Tick",
        ylabel = "Hidden Population Rate (Hz)",
        title = "SAAQ 1.5 Validation: Firing Rate vs Heartbeat",
    )
    plot!(p1, latent_df.tick, rate_overlay; label = "heartbeat_signal (scaled)", color = :crimson, linestyle = :dash)

    p2 = plot(
        latent_df.tick,
        latent_df.routing_entropy;
        label = "routing_entropy",
        color = :darkgreen,
        xlabel = "Tick",
        ylabel = "Routing Entropy",
        title = "Routing Entropy vs Heartbeat",
    )
    plot!(p2, latent_df.tick, entropy_overlay; label = "heartbeat_signal (scaled)", color = :crimson, linestyle = :dash)

    p3 = scatter(
        tick_df.tick,
        tick_df.best_walker;
        label = "best_walker",
        color = :purple4,
        markersize = 4,
        xlabel = "Tick",
        ylabel = "Best Walker",
        title = "Walker Activity vs Heartbeat",
    )
    plot!(p3, tick_df.tick, walker_overlay; label = "heartbeat_signal (scaled)", color = :crimson, linestyle = :dash)

    p4 = plot(
        latent_df.tick,
        latent_df.gpu_temp_c;
        label = "gpu_temp_c",
        color = :orange3,
        xlabel = "Tick",
        ylabel = "Telemetry",
        title = "Raw Telemetry Channels",
    )
    plot!(p4, latent_df.tick, latent_df.gpu_power_w; label = "gpu_power_w", color = :royalblue3)
    plot!(p4, latent_df.tick, latent_df.cpu_tctl_c; label = "cpu_tctl_c", color = :forestgreen)
    plot!(p4, latent_df.tick, latent_df.cpu_package_power_w; label = "cpu_package_power_w", color = :brown3)
    plot!(p4, latent_df.tick, power_overlay; label = "heartbeat_signal (scaled)", color = :crimson, linestyle = :dash)

    plot(p1, p2, p3, p4; layout = (4, 1))
end

function main()
    latent_path = latent_input_path()
    tick_path = tick_input_path()
    output_file = output_path()

    latent_df = load_latent_data(latent_path)
    tick_df = load_tick_data(tick_path)
    fig = build_dashboard(latent_df, tick_df)
    savefig(fig, output_file)

    println("Loaded $(nrow(latent_df)) latent rows from $(latent_path)")
    println("Loaded $(nrow(tick_df)) tick rows from $(tick_path)")
    println("Saved dashboard to $(output_file)")
end

main()
