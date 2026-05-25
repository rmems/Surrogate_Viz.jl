using Test
using CSV
using DataFrames
using Statistics

include(joinpath(@__DIR__, "..", "src", "Surrogate_Viz.jl"))
using .SurrogateViz

@testset "SurrogateViz module exports" begin
    @test :imported_latent_path in names(SurrogateViz)
    @test :load_latent_df in names(SurrogateViz)
    @test :detect_delta_column in names(SurrogateViz)
    @test :maybe_entropy_column in names(SurrogateViz)
    @test :summarise_run in names(SurrogateViz)
    @test :pairwise_summary in names(SurrogateViz)
    @test :fmt in names(SurrogateViz)
    @test :to_float64_vec in names(SurrogateViz)
    @test :to_int_ms in names(SurrogateViz)
    @test :IMPORT_ROOT in names(SurrogateViz)
end

@testset "fmt — -0.0 normalization" begin
    @test SurrogateViz.fmt(0.0) == "0.0"
    @test SurrogateViz.fmt(-0.0) == "0.0"
    @test SurrogateViz.fmt(1.234567) == "1.234567"
    @test SurrogateViz.fmt(-1.5e-7) == "0.0"
    @test SurrogateViz.fmt(missing) == "-"
    @test SurrogateViz.fmt("hello") == "hello"
end

@testset "to_float64_vec — skips missing" begin
    @test SurrogateViz.to_float64_vec([1.0, 2.0, 3.0]) == [1.0, 2.0, 3.0]
    @test SurrogateViz.to_float64_vec([1.0, missing, 3.0]) == [1.0, 3.0]
    @test isempty(SurrogateViz.to_float64_vec([missing, missing]))
end

@testset "to_int_ms — rounding" begin
    @test SurrogateViz.to_int_ms(100.4) == 100
    @test SurrogateViz.to_int_ms(100.5) == 100
    @test SurrogateViz.to_int_ms(0.0) == 0
end

@testset "detect_delta_column" begin
    v15_df = DataFrame(saaq_delta_q_v15_target = [0.1], timestamp_ms = [0])
    legacy_df = DataFrame(saaq_delta_q_legacy_target = [0.2], timestamp_ms = [0])
    both_df = DataFrame(saaq_delta_q_v15_target = [0.1], saaq_delta_q_legacy_target = [0.2], timestamp_ms = [0])

    @test SurrogateViz.detect_delta_column([v15_df]) == :saaq_delta_q_v15_target
    @test SurrogateViz.detect_delta_column([both_df]) == :saaq_delta_q_v15_target
    @test SurrogateViz.detect_delta_column([legacy_df]) == :saaq_delta_q_legacy_target

    @test_throws ErrorException SurrogateViz.detect_delta_column(DataFrame[])

    no_delta_df = DataFrame(timestamp_ms = [0], avg_pop_firing_rate_hz = [1.0])
    @test_throws ErrorException SurrogateViz.detect_delta_column([no_delta_df])
end

@testset "maybe_entropy_column" begin
    with_entropy = DataFrame(routing_entropy = [0.5], timestamp_ms = [0])
    without_entropy = DataFrame(timestamp_ms = [0], avg_pop_firing_rate_hz = [1.0])

    @test SurrogateViz.maybe_entropy_column([with_entropy]) == :routing_entropy
    @test SurrogateViz.maybe_entropy_column([without_entropy]) === nothing
    @test SurrogateViz.maybe_entropy_column(DataFrame[]) === nothing
end

@testset "summarise_run — neutral paired-run fixtures" begin
    control_off_df = DataFrame(
        timestamp_ms = [0, 100, 200, 300],
        saaq_delta_q_v15_target = [0.5, 0.6, 0.7, 0.8],
    )

    control_on_df = DataFrame(
        timestamp_ms = [0, 100, 200, 300],
        saaq_delta_q_v15_target = [1.5, 1.6, 1.7, 1.8],
        routing_entropy = [0.1, 0.2, 0.3, 0.4],
    )

    off_run = Dict{String,Any}("id" => "run_001", "heartbeat" => "heartbeat_off", "model" => "test_model", "telemetry_source" => "csv_re4_path_tracing_telemetry", "family" => "test")
    on_run = Dict{String,Any}("id" => "run_002", "heartbeat" => "heartbeat_on", "model" => "test_model", "telemetry_source" => "csv_re4_path_tracing_telemetry", "family" => "test")

    delta_col = :saaq_delta_q_v15_target
    entropy_col = :routing_entropy

    off_summary = SurrogateViz.summarise_run(control_off_df, off_run, delta_col, nothing)
    @test off_summary["rows"] == 4
    @test off_summary["mean_delta"] ≈ 0.65
    @test off_summary["final_delta"] == 0.8
    @test off_summary["mean_entropy"] === missing

    on_summary = SurrogateViz.summarise_run(control_on_df, on_run, delta_col, entropy_col)
    @test on_summary["rows"] == 4
    @test on_summary["mean_delta"] ≈ 1.65
    @test on_summary["mean_entropy"] ≈ 0.25
    @test on_summary["final_entropy"] == 0.4
end

@testset "pairwise_summary — neutral paired-run mechanics" begin
    control_off_df = DataFrame(
        timestamp_ms = [0, 100, 200],
        saaq_delta_q_v15_target = [0.5, 0.6, 0.7],
        routing_entropy = [0.1, 0.2, 0.3],
    )

    control_on_df = DataFrame(
        timestamp_ms = [0, 100, 200],
        saaq_delta_q_v15_target = [1.5, 1.6, 1.7],
        routing_entropy = [0.4, 0.5, 0.6],
    )

    delta_col = :saaq_delta_q_v15_target
    entropy_col = :routing_entropy

    joined, summary = SurrogateViz.pairwise_summary(control_off_df, control_on_df, delta_col, entropy_col)

    @test nrow(joined) == 3
    @test summary["paired_rows"] == 3
    @test summary["mean_delta_on_minus_off"] ≈ 1.0
    @test summary["max_abs_delta_on_minus_off"] ≈ 1.0
    @test summary["final_delta_on_minus_off"] == 1.0
    @test summary["mean_entropy_on_minus_off"] ≈ 0.3
    @test summary["final_entropy_on_minus_off"] == 0.3
end

@testset "pairwise_summary — missing entropy values" begin
    control_off_df = DataFrame(
        timestamp_ms = [0, 100, 200],
        saaq_delta_q_v15_target = [0.5, 0.6, 0.7],
        routing_entropy = [0.1, missing, 0.3],
    )

    control_on_df = DataFrame(
        timestamp_ms = [0, 100, 200],
        saaq_delta_q_v15_target = [1.5, 1.6, 1.7],
        routing_entropy = [0.4, 0.5, 0.6],
    )

    joined, summary = SurrogateViz.pairwise_summary(control_off_df, control_on_df, :saaq_delta_q_v15_target, :routing_entropy)

    @test nrow(joined) == 3
    @test summary["paired_rows"] == 3
    @test summary["mean_delta_on_minus_off"] ≈ 1.0
    @test haskey(summary, "mean_entropy_on_minus_off")
    @test summary["mean_entropy_on_minus_off"] ≈ 0.325
    @test haskey(summary, "final_entropy_on_minus_off")
    @test summary["final_entropy_on_minus_off"] ≈ 0.3
end

@testset "pairwise_summary — no entropy column" begin
    control_off_df = DataFrame(
        timestamp_ms = [0, 100],
        saaq_delta_q_v15_target = [0.5, 0.6],
    )

    control_on_df = DataFrame(
        timestamp_ms = [0, 100],
        saaq_delta_q_v15_target = [1.5, 1.6],
    )

    joined, summary = SurrogateViz.pairwise_summary(control_off_df, control_on_df, :saaq_delta_q_v15_target, nothing)

    @test nrow(joined) == 2
    @test summary["paired_rows"] == 2
    @test !haskey(summary, "mean_entropy_on_minus_off")
    @test !haskey(summary, "final_entropy_on_minus_off")
end