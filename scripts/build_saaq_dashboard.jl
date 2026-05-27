#!/usr/bin/env julia
# build_saaq_dashboard.jl
# Read normalized CSV tables from <normalized_dir> and emit a static
# HTML dashboard + summary.md under <report_dir>/.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Surrogate_Viz
const SV = Surrogate_Viz
using CSV
using DataFrames
import Dates

function _heatmap_latent_path(
    model_family, telemetry_source, heartbeat_enabled, run_id;
    import_root::AbstractString = SV.IMPORT_ROOT,
)
    condition_label = heartbeat_enabled ? "heartbeat_on" : "heartbeat_off"
    SV.validate_path_component("model_family", model_family)
    SV.validate_path_component("telemetry_source", telemetry_source)
    SV.validate_path_component("run_id", run_id)
    joinpath(import_root, model_family, telemetry_source, condition_label, run_id, "latent_telemetry.csv")
end

function delta_color(v, vmax)
    v == 0 && return "#e0e0e0"
    t = clamp(abs(v) / vmax, 0.0, 1.0)
    l = round(Int, 65 - t * 35)
    v > 0 ? "hsl(0,70%,$(l)%)" : "hsl(220,70%,$(l)%)"
end

function compute_heatmap_data(
    runs_df;
    import_root::AbstractString = SV.IMPORT_ROOT,
    bucket_count::Int = 20,
)
    heatmap_data = Dict{String,Vector{Float64}}()
    real_df = filter(:run_status => ==("real"), runs_df)
    isempty(real_df) && return heatmap_data

    models = unique(real_df[!, :model_family])
    for model in models
        model_df = filter(:model_family => ==(model), real_df)
        for repeat_idx in unique(model_df[!, :repeat_idx])
            repeat_df = filter(:repeat_idx => ==(repeat_idx), model_df)
            off_df_raw = filter(:heartbeat_enabled => ==(false), repeat_df)
            on_df_raw  = filter(:heartbeat_enabled => ==(true),  repeat_df)
            (isempty(off_df_raw) || isempty(on_df_raw)) && continue

            path_col = hasproperty(real_df, :model_slug) ? :model_slug : :model_family
            tel_col   = hasproperty(real_df, :telemetry_source) ? :telemetry_source : :telemetry_source

            path_off = _heatmap_latent_path(
                off_df_raw[1, path_col], off_df_raw[1, tel_col], false, off_df_raw[1, :run_id]; import_root)
            path_on  = _heatmap_latent_path(
                on_df_raw[1, path_col],  on_df_raw[1, tel_col],  true,  on_df_raw[1, :run_id];  import_root)
            (isfile(path_off) && isfile(path_on)) || continue

            df_off = CSV.read(path_off, DataFrame)
            df_on  = CSV.read(path_on,  DataFrame)

            frames = [df_off, df_on]
            common = intersect((Set(String.(names(df))) for df in frames)...)
            detected_col_name = "saaq_delta_q_v15_target"
            if !(detected_col_name in common)
                continue
            end
            detected_col = Symbol(detected_col_name)

            joined = DataFrame()
            try
                joined, _ = SV.pairwise_summary(df_off, df_on, detected_col, nothing)
            catch e
                (e isa ErrorException && occursin("overlapping timestamps", e.msg)) || rethrow(e)
                @debug "Skipping model=$(model) repeat=$(repeat_idx): no overlapping timestamps"
                continue
            end
            nrow(joined) == 0 && continue
            deltas_col = :delta_on_minus_off
            if !hasproperty(joined, deltas_col); continue; end
            deltas = collect(skipmissing(joined[!, deltas_col]))
            deltas = Float64.(deltas)
            isempty(deltas) && continue

            n = length(deltas)
            nb = bucket_count
            buckets = zeros(Float64, nb)
            counts  = zeros(Int, nb)
            for (i, val) in enumerate(deltas)
                b = min(nb, (i - 1) * nb ÷ n + 1)
                buckets[b] += val
                counts[b]  += 1
            end
            for b in 1:nb
                if counts[b] > 0
                    buckets[b] /= counts[b]
                end
            end

            key = "$(model) [r$(repeat_idx)]"
            heatmap_data[key] = buckets
        end
    end
    return heatmap_data
end

function build_heatmap_panel(heatmap_data; n_buckets=20)
    isempty(heatmap_data) && return ""
    vmax = maximum(maximum(abs, v) for v in values(heatmap_data))
    vmax = max(vmax, 1e-9)
    buf = IOBuffer()
    write(buf, """<div class="panel"><div class="panel-header">Delta Heatmap — treatment − baseline</div><div class="panel-body"><table class="heatmap-table"><thead><tr><th>Model</th>""")
    for i in 1:n_buckets; write(buf, "<th>$i</th>"); end
    write(buf, "</tr></thead><tbody>")
    for (model, buckets) in heatmap_data
        write(buf, "<tr><td class='hm-model'>$(html_escape(model))</td>")
        for i in 1:n_buckets
            val = (i <= length(buckets)) ? buckets[i] : 0.0
            color = delta_color(val, vmax)
            write(buf, """<td class='hm-cell' style='background:$(color)' title='$(round(val,digits=3))'></td>""")
        end
        write(buf, "</tr>")
    end
    write(buf, "</tbody></table></div></div>")
    String(take!(buf))
end

function html_escape(s)
    s = replace(string(s), "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'" => "&#39;")
    return s
end

function fmt_val(v)
    if ismissing(v) || v === missing
        return "&mdash;"
    elseif v === nothing
        return "&mdash;"
    elseif v isa Real
        return string(round(Float64(v), digits=4))
    else
        return string(v)
    end
end

function build_dashboard_html(runs_df, metrics_df, warnings_df; date_label, heatmap_data=Dict())
    buf = IOBuffer()
    write(buf, """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SAAQ Bundle Report — $(date_label)</title>
    <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 13px; color: #222; background: #f7f7f7; }
    .container { max-width: 1400px; margin: 0 auto; padding: 24px; }
    h1 { font-size: 22px; font-weight: 600; color: #111; margin-bottom: 4px; }
    .subtitle { color: #666; font-size: 12px; margin-bottom: 24px; }
    .panel { background: #fff; border: 1px solid #e0e0e0; border-radius: 6px; margin-bottom: 20px; }
    .panel-header { padding: 12px 16px; border-bottom: 1px solid #e0e0e0; font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: #555; background: #fafafa; border-radius: 6px 6px 0 0; }
    .panel-body { padding: 16px; }
    table { width: 100%; border-collapse: collapse; font-size: 12px; }
    th { text-align: left; padding: 6px 10px; background: #f0f0f0; border-bottom: 2px solid #ddd; font-weight: 600; color: #333; white-space: nowrap; }
    td { padding: 6px 10px; border-bottom: 1px solid #eee; vertical-align: top; }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: #f9f9f9; }
    .status-real    { color: #1a7f37; font-weight: 600; }
    .status-synthetic { color: #6a7fe8; font-weight: 600; }
    .status-skipped  { color: #9a6700; }
    .status-failed   { color: #cf222e; font-weight: 600; }
    .badge { display: inline-block; padding: 2px 6px; border-radius: 10px; font-size: 11px; font-weight: 600; }
    .badge-real    { background: #dafbe1; color: #1a7f37; }
    .badge-synthetic { background: #e8edff; color: #4c56b8; }
    .badge-skipped  { background: #fff8c5; color: #9a6700; }
    .badge-failed   { background: #ffebe9; color: #cf222e; }
    .summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 20px; }
    .card { background: #fff; border: 1px solid #e0e0e0; border-radius: 6px; padding: 14px 16px; }
    .card-label { font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em; color: #888; margin-bottom: 4px; }
    .card-value { font-size: 24px; font-weight: 700; color: #111; }
    .card-sub { font-size: 11px; color: #888; margin-top: 2px; }
    .col-model   { min-width: 140px; }
    .col-status  { min-width: 90px; }
    .col-rule    { min-width: 130px; }
    .col-telemetry { min-width: 140px; }
    .col-repeat  { min-width: 70px; text-align: center; }
    .col-ticks   { min-width: 70px; text-align: right; }
    .col-metrics { min-width: 80px; text-align: center; }
    .col-warn    { min-width: 60px; text-align: center; }
.heatmap-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
    .heatmap-table th { font-size: 10px; padding: 3px 4px; text-align: center; }
    .heatmap-table td.hm-cell { width: 3%; min-width: 18px; height: 28px; border: 1px solid #fff; }
    td.hm-model { text-align: left; padding: 4px 8px; font-size: 11px; white-space: nowrap; width: 160px; }
    </style>
    </head>
    <body>
    <div class="container">
    <h1>SAAQ Experiment Bundle Report</h1>
    <div class="subtitle">Generated: $(date_label)</div>
    """)

    n_runs = nrow(runs_df)
    n_real = count(isequal("real"), runs_df.run_status)
    n_synth = count(isequal("synthetic"), runs_df.run_status)
    n_skipped = count(isequal("skipped"), runs_df.run_status)
    n_failed = count(isequal("failed"), runs_df.run_status)
    n_warnings = nrow(warnings_df)

    write(buf, """
    <div class="summary-cards">
      <div class="card">
        <div class="card-label">Total Runs</div>
        <div class="card-value">$(n_runs)</div>
        <div class="card-sub">ingested bundles</div>
      </div>
      <div class="card">
        <div class="card-label">Real</div>
        <div class="card-value" style="color:#1a7f37">$(n_real)</div>
        <div class="card-sub">completed</div>
      </div>
      <div class="card">
        <div class="card-label">Synthetic</div>
        <div class="card-value" style="color:#4c56b8">$(n_synth)</div>
        <div class="card-sub">fixture runs</div>
      </div>
      <div class="card">
        <div class="card-label">Skipped</div>
        <div class="card-value" style="color:#9a6700">$(n_skipped)</div>
        <div class="card-sub">incomplete</div>
      </div>
      <div class="card">
        <div class="card-label">Failed</div>
        <div class="card-value" style="color:#cf222e">$(n_failed)</div>
        <div class="card-sub">errors</div>
      </div>
      <div class="card">
        <div class="card-label">Warnings</div>
        <div class="card-value">$(n_warnings)</div>
        <div class="card-sub">recorded</div>
      </div>
    </div>
    """)

    write(buf, """
    <div class="panel">
    <div class="panel-header">Run Summary</div>
    <div class="panel-body">
    <table>
    <thead>
    <tr>
      <th class="col-model">Run ID</th>
      <th class="col-status">Status</th>
      <th class="col-model">Model Family</th>
      <th class="col-rule">SAAQ Rule</th>
      <th class="col-telemetry">Telemetry Source</th>
      <th class="col-repeat">Repeat</th>
      <th class="col-ticks">Ticks</th>
      <th class="col-metrics">Metrics</th>
      <th class="col-warn">Warnings</th>
    </tr>
    </thead>
    <tbody>
    """)

    for row in eachrow(runs_df)
        run_id = string(row.run_id)
        status = string(row.run_status)
        status_class = "badge-$(status)"
        hb_label = row.heartbeat_enabled ? "&nbsp;<span style='color:#6a7fe8'>♦</span>" : ""

        run_metrics = filter(:run_id => ==(run_id), metrics_df)
        n_run_metrics = nrow(run_metrics)
        n_row_warnings = count(isequal(run_id), warnings_df.run_id)

        write(buf, "<tr>")
        write(buf, "<td><code>$(run_id)</code></td>")
        write(buf, "<td><span class='badge $(status_class)'>$(status)</span>$(hb_label)</td>")
        write(buf, "<td>$(fmt_val(row.model_family))</td>")
        write(buf, "<td><code>$(fmt_val(row.saaq_formula_version))</code></td>")
        write(buf, "<td><code>$(fmt_val(row.telemetry_source))</code></td>")
        write(buf, "<td class='col-repeat'>$(fmt_val(row.repeat_idx)) / $(fmt_val(row.repeat_count))</td>")
        write(buf, "<td class='col-ticks'>$(fmt_val(row.ticks_effective))</td>")
        write(buf, "<td class='col-metrics'>$(n_run_metrics)</td>")
        write(buf, "<td class='col-warn'>$(n_row_warnings)</td>")
        write(buf, "</tr>\n")
    end

    write(buf, """
    </tbody>
    </table>
    </div>
    </div>
    """)
    write(buf, build_heatmap_panel(heatmap_data))
    if nrow(warnings_df) > 0
        write(buf, """
        <div class="panel">
        <div class="panel-header">Warnings</div>
        <div class="panel-body">
        <table>
        <thead>
        <tr>
          <th>Run ID</th>
          <th>Category</th>
          <th>Message</th>
          <th>Severity</th>
        </tr>
        </thead>
        <tbody>
        """)
        for row in eachrow(warnings_df)
            write(buf, "<tr>")
            write(buf, "<td><code>$(html_escape(row.run_id))</code></td>")
            write(buf, "<td>$(html_escape(fmt_val(row.warning_category)))</td>")
            write(buf, "<td>$(html_escape(fmt_val(row.warning_message)))</td>")
            write(buf, "<td>$(html_escape(fmt_val(row.severity)))</td>")
            write(buf, "</tr>\n")
        end
        write(buf, "</tbody></table></div></div>\n")
    end

    write(buf, """
    </div>
    </body>
    </html>
    """)
    return String(take!(buf))
end

function build_summary_md(runs_df, metrics_df, warnings_df; date_label)
    buf = IOBuffer()
    write(buf, "# SAAQ Experiment Bundle Report\n\n")
    write(buf, "**Generated:** $(date_label)\n\n\n")

    write(buf, "## Run Overview\n\n")
    write(buf, "| Run ID | Status | Model Family | SAAQ Rule | Telemetry | Repeat | Ticks | Metrics | Warnings |\n")
    write(buf, "|---|---|---|---|---|---|---|---|---|\n")
    for row in eachrow(runs_df)
        run_id = string(row.run_id)
        n_run_metrics = count(isequal(run_id), metrics_df.run_id)
        n_warns = count(isequal(run_id), warnings_df.run_id)
        write(buf, "| `$(row.run_id)` | $(row.run_status) | $(row.model_family) | `$(row.saaq_formula_version)` | `$(row.telemetry_source)` | $(row.repeat_idx)/$(row.repeat_count) | $(row.ticks_effective) | $(n_run_metrics) | $(n_warns) |\n")
    end
    write(buf, "\n")

    if nrow(warnings_df) > 0
        write(buf, "## Warnings\n\n")
        write(buf, "| Run ID | Category | Message | Severity |\n")
        write(buf, "|---|---|---|---|\n")
        for row in eachrow(warnings_df)
            write(buf, "| `$(row.run_id)` | $(row.warning_category) | $(row.warning_message) | $(row.severity) |\n")
        end
        write(buf, "\n")
    end

    return String(take!(buf))
end

function main()
    if length(ARGS) < 2
        println(stderr, "Usage: julia --project=. scripts/build_saaq_dashboard.jl <normalized_dir> <report_dir>")
        println(stderr, "")
        println(stderr, "  Reads runs_table.csv, metrics_table.csv, warnings_table.csv from <normalized_dir>,")
        println(stderr, "  generates dashboard.html + summary.md under <report_dir>/<date_label>/.")
        exit(1)
    end

    normalized_dir = ARGS[1]
    report_dir = ARGS[2]

    if !isdir(normalized_dir)
        println(stderr, "Error: normalized directory not found: $(normalized_dir)")
        exit(1)
    end

    runs_path = joinpath(normalized_dir, "runs_table.csv")
    metrics_path = joinpath(normalized_dir, "metrics_table.csv")
    warnings_path = joinpath(normalized_dir, "warnings_table.csv")

    if !isfile(runs_path)
        println(stderr, "Error: runs_table.csv not found at $(runs_path)")
        exit(1)
    end

    runs_df = CSV.read(runs_path, DataFrame)
    metrics_df = isfile(metrics_path) ? CSV.read(metrics_path, DataFrame) : DataFrame(run_id=String[], metric_name=String[], metric_value=Any[], metric_category=String[])
    warnings_df = isfile(warnings_path) ? CSV.read(warnings_path, DataFrame) : DataFrame(run_id=String[], warning_category=String[], warning_message=String[], tensor_name=Union{String,Nothing}[], severity=String[])

    date_label = Dates.format(Dates.today(), "yyyy-mm-dd")
    out_dir = joinpath(report_dir, date_label)
    mkpath(out_dir)

    heatmap_data = compute_heatmap_data(runs_df)
    dashboard_html = build_dashboard_html(runs_df, metrics_df, warnings_df; date_label, heatmap_data)
    summary_md = build_summary_md(runs_df, metrics_df, warnings_df; date_label)

    dashboard_path = joinpath(out_dir, "dashboard.html")
    summary_path = joinpath(out_dir, "summary.md")

    open(dashboard_path, "w") do f
        write(f, dashboard_html)
    end
    open(summary_path, "w") do f
        write(f, summary_md)
    end

    cp(runs_path, joinpath(out_dir, "runs_table.csv"), force=true)
    if isfile(metrics_path)
        cp(metrics_path, joinpath(out_dir, "metrics_table.csv"), force=true)
    end
    if isfile(warnings_path)
        cp(warnings_path, joinpath(out_dir, "warnings_table.csv"), force=true)
    end

    println("✓ Dashboard written to: $(out_dir)/")
    println("  dashboard.html")
    println("  summary.md")
    println("  runs_table.csv (copied)")
    println("  metrics_table.csv (copied)")
    println("  warnings_table.csv (copied)")
end

main()
