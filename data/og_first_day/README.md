=== OG (Original) PNG Data Set Up ===

This directory (or manifest) holds the canonical telemetry from the first SAAQ real-weights experiment.

Canonical external source (do not modify; user-specified external first-day data dir):
  SAAQ-Latent-Telemetry/first-day-testing-real-weights/ (or equivalent path provided for the original PNGs)

Key OG files (these produced the original map_*.png walker/spiking graphs):
- fourth-test/telemetry_olmoe_math_logic.txt + map_olmoe_math_logic.png (math logic case)
- third-test/snn_latent_telemetry.csv + map_olmoe_rust_syntax_logic.png + .txt (rust case)
- second-test/ (english case)
- first-test-failed/ (early attempt)

The files in ../ (the parent data/) telemetry_math_logic.txt and snn_latent_telemetry.csv are direct copies of the OG ones from the above path.

Revived plot_latent_space.jl (and any first-day/OG wrapper) must be runnable against these exact files (or the external path) and reproduce (or CUDA-enhance) the original PNGs.

See the main plan.md (Grok Build 0.1 model) for 'OG png data set up' goal, corinth-canal + myelin inspiration for the pure-Julia CUDA visual kernels, and generalized (no OLMoE-specific) first-experiment revival.

Grok Build 0.1 model
