using Pkg
Pkg.add(["SymbolicRegression", "CSV", "DataFrames", "Plots"])

using SymbolicRegression
using CSV
using DataFrames
using Plots

println("1. Loading raw Ship of Theseus telemetry...")
# File from gaming-telemetry repo
raw_data = CSV.read("telemetry.csv", Dataframe)

# To start out let's keep the test fast
df = first(raw_data, 1000)

println("2. Simulating the SNN and Target (y) variables...")
# SIMULATE SNN: For I am pretending the SNN firing rate is tightly correlated to GPU power
# I am going to divide by 400.0 to normalize it between 0.0 and 1.0
total_power = df.gpu_power_w .+ df.cpu_package_power_w
ideal_y_target = total_power ./ 500.0 # Normalized Target

println("3. Formatting data for Symbolic Regression...")
# X must be a matrix where each row is a feature (Input Variable)
# Features: [GPU Temp, GPU Power, CPU Power, SNN Firing Rate]
X = hcat(df.gpu_temp_c, df.gpu_power_w, df.cpu_package_power_w, snn_firing_rate)'

# y is our 1D array (The Answer Key)
y = ideal_y_target

println("4. Launching Evolutionary Math Search (This will take a momemt)...")
# We give Julia basic math operations to build equation
options = SymbolicRegression.Options(
    binary_operators=[+,-,*,/],
    npopulations=20,
    parsimony=0.01 # This forces it to clean simple equations
)

# Run the search!
hof = EquationSearch(X, y, niterations=30, options=options)

println("\n=== DISCOVERY COMPLETE ===")
println("Dominant Equations FOund:")
print(hof)