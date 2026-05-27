using Pkg
Pkg.activate(@__DIR__)

using CSV
using DataFrames
import Dates
import Random

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")
ENV["QT_QPA_PLATFORM"] = get(ENV, "QT_QPA_PLATFORM", "offscreen")
using Plots

const TICK_PATTERN = r"^tick=(\d+) best_walker=(\d+) elapsed_us=(\d+) condition_signal=([-+0-9.eE]+) gpu_temp_c=([-+0-9.eE]+) gpu_power_w=([-+0-9.eE]+) cpu_tctl_c=([-+0-9.eE]+) cpu_package_power_w=([-+0-9.eE]+)$"

const MODELS = [
    "olmoe-1b-7b",                                    # olmoe_baseline
    "qwen3-moe-i1-GGUF IQ3_M.gguf",                   # qwen3_moe_i1_iq3_m
    "gemma-4-26B-A4B-it-UD-IQ4_NL.gguf",              # gemma4_26b_a4b_iq4_nl
    "DeepSeek-Coder-V2-Lite-Instruct-Q6_K_L.gguf",    # deepseek_coder_v2_lite_q6_k_l
    "L3.2-8X3B-MOE-Dark-Champion-Inst-18.4B-uncen-ablit_D_AU-q5_k_m.gguf",  # llama_3_2_dark_champion_q5_k_m
    # Onboarded in corinth-canal LLM-models-onboarding PR #68
    "zaya1_8b_q8_0",                                  # Zaya 1 (Abiray/ZAYA1-8B-GGUF)
    "glm46v_flash_q8_0",                              # GLM-4.6V-Flash
    "kimi_vl_a3b_q6_k",                               # Kimi-VL-A3B-Instruct
    "marco_nano_base_q8_0",                           # Marco-Nano-Base
]

function model_name()
    m = get(ENV, "MODEL", MODELS[1])  # default olmoe-1b-7b
    m in MODELS || @warn "Unknown MODEL=$(m); expected one of $(MODELS)"
    return m
end

function default_dashboard_path()
    stamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    suffix = Random.randstring(6)
    dir = joinpath(@__DIR__, "outputs", model_name(), "dashboards", string(stamp, "_", suffix))
    mkpath(dir)
    return joinpath(dir, "saaq1_5_validation_dashboard.png")
end

latent_input_path() = get(ARGS, 1, joinpath(@__DIR__, "data", model_name(), "snn_latent_telemetry.csv"))
tick_input_path() = get(ARGS, 2, joinpath(@__DIR__, "data", model_name(), "tick_telemetry.txt"))
output_path() = length(ARGS) >= 3 ? ARGS[3] : default_dashboard_path()

function load_latent_data(path::AbstractString)
    df = CSV.read(path, DataFrame)
    required = [
        :timestamp_ms,
        :avg_pop_firing_rate_hz,
        :routing_entropy,
        :condition_signal,
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
    condition_signal = Float64[]
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
        push!(condition_signal, parse(Float64, match_result.captures[4]))
        push!(gpu_temp_c, parse(Float64, match_result.captures[5]))
        push!(gpu_power_w, parse(Float64, match_result.captures[6]))
        push!(cpu_tctl_c, parse(Float64, match_result.captures[7]))
        push!(cpu_package_power_w, parse(Float64, match_result.captures[8]))
    end

    isempty(ticks) && error("No tick data found in $(path). Expected condition-aware telemetry lines.")

    return DataFrame(
        tick = ticks,
        best_walker = best_walkers,
        elapsed_us = elapsed_us,
        condition_signal = condition_signal,
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

    rate_overlay = scaled_overlay(latent_df[!, :condition_signal], latent_df[!, :avg_pop_firing_rate_hz])
    entropy_overlay = scaled_overlay(latent_df[!, :condition_signal], latent_df[!, :routing_entropy])
    walker_overlay = scaled_overlay(tick_df[!, :condition_signal], tick_df[!, :best_walker])
    power_overlay = scaled_overlay(latent_df[!, :condition_signal], latent_df[!, :gpu_power_w])

    p1 = plot(
        latent_df.tick,
        latent_df.avg_pop_firing_rate_hz;
        label = "avg_pop_firing_rate_hz",
        color = :navy,
        xlabel = "Tick",
        ylabel = "Hidden Population Rate (Hz)",
        title = "SAAQ 1.5 Validation: Firing Rate vs Control Signal",
    )
    plot!(p1, latent_df.tick, rate_overlay; label = "condition_signal (scaled)", color = :crimson, linestyle = :dash)

    p2 = plot(
        latent_df.tick,
        latent_df.routing_entropy;
        label = "routing_entropy",
        color = :darkgreen,
        xlabel = "Tick",
        ylabel = "Routing Entropy",
        title = "Routing Entropy vs Control Signal",
    )
    plot!(p2, latent_df.tick, entropy_overlay; label = "condition_signal (scaled)", color = :crimson, linestyle = :dash)

    p3 = scatter(
        tick_df.tick,
        tick_df.best_walker;
        label = "best_walker",
        color = :purple4,
        markersize = 4,
        xlabel = "Tick",
        ylabel = "Best Walker",
        title = "Walker Activity vs Control Signal",
    )
    plot!(p3, tick_df.tick, walker_overlay; label = "condition_signal (scaled)", color = :crimson, linestyle = :dash)

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
    plot!(p4, latent_df.tick, power_overlay; label = "condition_signal (scaled)", color = :crimson, linestyle = :dash)

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
