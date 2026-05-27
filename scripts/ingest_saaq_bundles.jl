#!/usr/bin/env julia
# ingest_saaq_bundles.jl
# Walk a directory tree of corinth-canal run bundles, load each one,
# and write normalized CSV tables to the output directory.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Surrogate_Viz
using CSV
using DataFrames

function main()
    if length(ARGS) < 2
        println(stderr, "Usage: julia --project=. scripts/ingest_saaq_bundles.jl <input_dir> <output_dir>")
        println(stderr, "")
        println(stderr, "  Walks <input_dir> recursively, finds all run_manifest.json files,")
        println(stderr, "  loads each bundle, and writes normalized CSV tables to <output_dir>/.")
        exit(1)
    end

    input_dir = ARGS[1]
    output_dir = ARGS[2]

    if !isdir(input_dir)
        println(stderr, "Error: input directory not found: $(input_dir)")
        exit(1)
    end

    mkpath(output_dir)

    println("Ingesting bundles from: $(input_dir)")
    println("Writing output to:      $(output_dir)")

runs_df, metrics_df, warnings_df = normalize_bundles_dir(input_dir)

    runs_path = joinpath(output_dir, "runs_table.csv")
    metrics_path = joinpath(output_dir, "metrics_table.csv")
    warnings_path = joinpath(output_dir, "warnings_table.csv")

    CSV.write(runs_path, runs_df)
    CSV.write(metrics_path, metrics_df)
    if nrow(warnings_df) > 0
        CSV.write(warnings_path, warnings_df)
    end

    println("✓ Ingested $(nrow(runs_df)) runs")
    println("  runs_table.csv:     $(runs_path)")
    println("  metrics_table.csv:  $(metrics_path)")
    if nrow(warnings_df) > 0
        println("  warnings_table.csv: $(warnings_path)")
    end
end

main()
