# Dormant harness for latent SAAQ equation discovery using true SNN signals

using SymbolicRegression.Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using SymbolicRegression
using CSV
using DataFrames

const REQUIRED_COLS = [
    :avg_pop_firing_rate_hz,
    :membrane_dv_dt,
    :routing_entropy,
    :saaq_delta_q_prev,
    :saaq_delta_q_target,
]

csv_path = "snn_latent_telemetry.csv"

println("1) Loading latent telemetry from $(csv_path)...")
if !isfile(csv_path)
    error("Missing telemetry file: $(csv_path). Run corinth-canal to generate it first.")
end

df = CSV.read(csv_path, DataFrame)

missing_cols = setdiff(REQUIRED_COLS, propertynames(df))
if !isempty(missing_cols)
    error("Telemetry is missing required column(s): $(join(string.(missing_cols), ", ")). Check the Rust exporter schema.")
end

println("2) Building feature matrix X and target y...")
X = Matrix{Float64}(hcat(
    df.avg_pop_firing_rate_hz,
    df.membrane_dv_dt,
    df.routing_entropy,
    df.saaq_delta_q_prev,
)')

y = Float64.(df.saaq_delta_q_target)

println("3) Configuring symbolic regression (interpretability-first)...")
options = Options(
    binary_operators=[+, -, *, /],
    unary_operators=[exp, sqrt, square],
    maxsize=15,           # keep equations short for Rust MoE integration
    parsimony=0.01,       # push toward simpler expressions
    npopulations=20,
)

println("4) Launching evolutionary search (this may take a moment)...")
hof = equation_search(
    X,
    y,
    niterations=30,
    options=options,
    variable_names=[
        "avg_pop_firing_rate_hz",
        "membrane_dv_dt",
        "routing_entropy",
        "saaq_delta_q_prev",
    ],
)

println("\n=== Pareto front (dominant equations) ===")
dominating = calculate_pareto_frontier(hof)
for member in dominating
    println("Loss: $(member.loss)  Complexity: $(member.complexity)  Eq: $(member.tree)")
end
