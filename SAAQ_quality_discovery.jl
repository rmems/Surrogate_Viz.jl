# SAAQ quality-target equation discovery (candidate SAAQ 2.0 evidence)
#
# Sibling to SAAQ_latent_discovery.jl that breaks the circular fit flagged in
# grok-ozempic beads goz-otdnlk: there, `TARGET_COL = :saaq_delta_q_target`
# asks SymbolicRegression to rediscover the hand-written formula that
# *generated* the target column, which can never tell us whether SAAQ predicts
# quantization quality.
#
# This script instead consumes the τ-sweep quality CSV produced by
# grok-ozempic `scripts/grok1_tau_quality_sweep.py` (or any CSV with a real
# quality column). Target defaults to `reconstruction_cosine`
# (cos(w, α·t) with the optimal scale); features are signals available at
# quantization time.
#
# Feature notes:
#   The Part-1 CSV carries tensor statistics (rms, kurtosis, mean_abs, std),
#   the control (gif_threshold) and the outcome (sparsity). If the CSV has
#   been joined with corinth-canal latent telemetry first, activity columns
#   (avg_pop_firing_rate_hz, membrane_dv_dt, routing_entropy) can simply be
#   named in FEATURE_COLS.
#
# Environment:
#   QUALITY_CSV    (required) path to the quality CSV
#   TARGET_COL     default "reconstruction_cosine"
#   FEATURE_COLS   default "gif_threshold,rms,kurtosis,mean_abs,std"
#   SR_ITERATIONS  default "30"; 0 = dry run (validate + manifest only)
#   OUT_DIR        default outputs/quality_discovery/<csv-stem>/
#
# IMPORTANT: the discovered formula is *candidate* SAAQ 2.0 evidence only —
# it must not overwrite the SaaqV1_5SqrtRate coefficients in corinth-canal
# `src/latent.rs` (goz-otdnlk).

using Pkg

# Only take over the active project when run as a script. Activating (and
# especially instantiating) at load time would switch the caller's project out
# from under them when this file is `include`d — which the smoke tests do, and
# instantiate() would resolve the whole dependency tree on every test run.
if abspath(PROGRAM_FILE) == @__FILE__
    Pkg.activate(@__DIR__)
    Pkg.instantiate()
end

using CSV
using DataFrames
import JSON
import SymbolicRegression

const REPO_ROOT = @__DIR__

# Signals that exist at quantization time in the Part-1 sweep CSV. A CSV that
# has been outer-joined with latent telemetry can additionally offer
# :avg_pop_firing_rate_hz, :membrane_dv_dt, :routing_entropy — name them in
# FEATURE_COLS and they are validated like any other column. `sparsity` is
# deliberately NOT a default: it is a τ-outcome, and fitting cosine against it
# is nearly-trivial algebra — leakage, not discovery. Opt back in via
# FEATURE_COLS if you want the tradeoff curve.
const DEFAULT_FEATURE_COLS = [
    :gif_threshold,
    :rms,
    :kurtosis,
    :mean_abs,
    :std,
]

const DEFAULT_TARGET_COL = :reconstruction_cosine

function parse_symbol_list(raw::AbstractString)
    cols = [Symbol(strip(x)) for x in split(raw, ",") if !isempty(strip(x))]
    isempty(cols) && error("Empty column list: $(raw)")
    return cols
end

function validate_columns(df::DataFrame, required::Vector{Symbol})
    missing_cols = setdiff(required, propertynames(df))
    isempty(missing_cols) || error("CSV missing required column(s): $(join(string.(missing_cols), ", ")): $(propertynames(df))")
end

function build_feature_matrix(df::DataFrame, features::Vector{Symbol}, target::Symbol)
    X = Matrix{Float64}(hcat((Float64.(df[!, col]) for col in features)...))'
    y = Float64.(df[!, target])
    return X, y
end

# Rows with a non-finite value in any selected column carry no information for
# the fit — the sweep emits NaN cosine for degenerate tensors (nothing fires,
# or w == 0, where the metric is honestly undefined rather than zero), and NaN
# kurtosis for constant tensors. equation_search cannot ingest non-finite X.
function drop_nonfinite_rows(df::DataFrame, cols::Vector{Symbol})
    keep = reduce(.&, (
        broadcast(v -> !ismissing(v) && isfinite(Float64(v)), df[!, col])
        for col in cols
    ))
    n_dropped = count(.!keep)
    n_dropped > 0 && println("Dropped $(n_dropped) row(s) with non-finite values in $(join(string.(cols), ", "))")
    return df[keep, :]
end

function out_dir_for(csv_path::AbstractString)
    stem = splitext(basename(csv_path))[1]
    # Path components must not contain separators or traversal — refuse odd
    # names rather than sanitizing silently.
    (occursin(r"^[A-Za-z0-9._-]+$", stem) && !occursin(r"^\.+$", stem)) ||
        error("CSV basename $(stem) is not a safe output directory component")
    return joinpath(REPO_ROOT, "outputs", "quality_discovery", stem)
end

function write_metadata(out_dir::AbstractString;
    csv_path::AbstractString,
    feature_cols::Vector{Symbol},
    target_col::Symbol,
    niterations::Int,
)
    mkpath(out_dir)
    meta = Dict{String,Any}(
        "source_csv" => csv_path,
        "discovery_mode" => "external_quality_target",
        "feature_columns" => string.(feature_cols),
        "target_column" => string(target_col),
        "niterations" => niterations,
        "goz_otdnlk" => "candidate SAAQ 2.0 evidence; does NOT overwrite SaaqV1_5SqrtRate coefficients",
        "binary_operators" => ["+", "-", "*", "/"],
        "unary_operators" => ["exp", "sqrt", "square"],
        "maxsize" => 15,
        "parsimony" => 0.01,
    )
    open(joinpath(out_dir, "sr_manifest.json"), "w") do io
        JSON.print(io, meta, 2)
    end
    return meta
end

function main()
    csv_path = get(ENV, "QUALITY_CSV", nothing)
    csv_path === nothing &&
        error("QUALITY_CSV is required: path to a grok1_tau_quality_sweep.py CSV")
    isfile(csv_path) || error("QUALITY_CSV not found: $(csv_path)")

    feature_cols = let v = get(ENV, "FEATURE_COLS", nothing)
        v === nothing ? DEFAULT_FEATURE_COLS : parse_symbol_list(v)
    end
    target_col = Symbol(get(ENV, "TARGET_COL", string(DEFAULT_TARGET_COL)))
    target_col in feature_cols &&
        error("TARGET_COL $(target_col) also appears in FEATURE_COLS — a circular self-fit")
    niterations = parse(Int, get(ENV, "SR_ITERATIONS", "30"))
    niterations >= 0 || error("SR_ITERATIONS must be >= 0 (0 = dry run), got $(niterations)")

    df = CSV.read(csv_path, DataFrame)
    validate_columns(df, vcat(feature_cols, [target_col]))
    df = drop_nonfinite_rows(df, vcat(feature_cols, [target_col]))
    nrow(df) > 0 || error("No usable rows in $(csv_path) after dropping non-finite values")

    X, y = build_feature_matrix(df, feature_cols, target_col)
    println("Feature matrix: $(size(X)) rows=$(size(X, 2)), features=$(size(X, 1))")
    println("Target vector: $(length(y)) samples ($(target_col))")

    # get() would evaluate out_dir_for eagerly even when OUT_DIR is set.
    out_dir = haskey(ENV, "OUT_DIR") ? ENV["OUT_DIR"] : out_dir_for(csv_path)
    # A rerun (or a dry run) must not leave an older pareto_front.csv paired
    # with this run's manifest — clear it before writing new metadata.
    let stale = joinpath(out_dir, "pareto_front.csv")
        isfile(stale) && rm(stale)
    end
    write_metadata(out_dir;
        csv_path = csv_path,
        feature_cols = feature_cols,
        target_col = target_col,
        niterations = niterations,
    )
    println("Metadata written to $(out_dir)/sr_manifest.json")

    if niterations > 0
        println("Launching SR search ($(niterations) iterations)...")
        sr_opts = SymbolicRegression.Options(
            binary_operators = [+, -, *, /],
            unary_operators = [exp, sqrt, SymbolicRegression.square],
            maxsize = 15,
            parsimony = 0.01,
            npopulations = 20,
            output_directory = out_dir,
        )
        hof = SymbolicRegression.equation_search(X, y; niterations = niterations, options = sr_opts,
            variable_names = string.(feature_cols))
        println("\n=== Pareto front ($(target_col)) ===")
        dominating = SymbolicRegression.calculate_pareto_frontier(hof)
        for member in dominating
            comp = SymbolicRegression.compute_complexity(member, sr_opts)
            println("Loss: $(member.loss)  Complexity: $(comp)  Eq: $(member.tree)")
        end
        open(joinpath(out_dir, "pareto_front.csv"), "w") do io
            println(io, "complexity,loss,equation")
            for member in dominating
                comp = SymbolicRegression.compute_complexity(member, sr_opts)
                println(io, "$(comp),$(member.loss),\"$(replace(string(member.tree), "\"" => "\"\""))\"")
            end
        end
    else
        println("SR_ITERATIONS=0 — skipping SR search (dry run)")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
