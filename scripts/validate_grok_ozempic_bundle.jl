#!/usr/bin/env julia
# validate_grok_ozempic_bundle.jl
# Validate a single grok-ozempic validation report bundle.
# Exit code 0 = valid, non-zero = invalid.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

const SV = Base.require(Base.PkgId(Base.UUID("0e7d9c34-7da8-46ec-ad35-4cb1b8ff7bae"), "Surrogate_Viz"))

function main()
    if length(ARGS) < 1
        println(stderr, "Usage: julia --project=. scripts/validate_grok_ozempic_bundle.jl <bundle_dir>")
        exit(1)
    end

    bundle_dir = ARGS[1]

    if !isdir(bundle_dir)
        println(stderr, "Error: directory not found: $(bundle_dir)")
        exit(1)
    end

    is_valid, errors = SV.validate_grok_ozempic_bundle(bundle_dir)

    if is_valid
        println("✓ Bundle validation passed: $(bundle_dir)")
        try
            bundle = SV.load_grok_ozempic_bundle(bundle_dir)
            println("  status:               $(bundle.report.status)")
            println("  source_tensor_count:  $(bundle.report.source_tensor_count)")
            println("  artifact_tensor_count: $(bundle.report.artifact_tensor_count)")
            println("  router_count:         $(bundle.report.router_count)")
            println("  byte_accounting:      $(bundle.report.byte_accounting_result)")
            println("  failures:             $(length(bundle.report.failures))")
            println("  warnings:             $(length(bundle.report.warnings))")
        catch e
            println(stderr, "Error: bundle passed basic validation but failed to load: $(e)")
            exit(1)
        end
        exit(0)
    else
        println(stderr, "✗ Bundle validation FAILED: $(bundle_dir)")
        for err in errors
            println(stderr, "  - $(err)")
        end
        exit(1)
    end
end

main()
