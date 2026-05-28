Base.@kwdef struct GrokOzempicFailure
    category::String = ""
    tensor::Union{Nothing,String} = nothing
    message::String = ""
end

Base.@kwdef struct GrokOzempicWarning
    category::String = ""
    tensor::Union{Nothing,String} = nothing
    message::String = ""
end

Base.@kwdef struct GrokOzempicReport
    status::String = "UNKNOWN"
    source_tensor_count::Int = 0
    artifact_tensor_count::Int = 0
    router_count::Int = 0
    protected_router_violations::Int = 0
    protected_norm_violations::Int = 0
    expert_association_count::Int = 0
    unknown_unresolved_warning_count::Int = 0
    checksum_coverage::String = ""
    source_total_bytes::Int = 0
    artifact_total_bytes::Int = 0
    byte_accounting_result::String = ""
    failures::Vector{GrokOzempicFailure} = GrokOzempicFailure[]
    warnings::Vector{GrokOzempicWarning} = GrokOzempicWarning[]
    extra::Dict{String,Any} = Dict{String,Any}()
end

Base.@kwdef struct GrokOzempicBundle
    report::GrokOzempicReport
    bundle_path::String = ""
end

const GROK_OZEMPIC_REPORT_FIELDS = Set{Symbol}([
    :status, :source_tensor_count, :artifact_tensor_count, :router_count,
    :protected_router_violations, :protected_norm_violations,
    :expert_association_count, :unknown_unresolved_warning_count,
    :checksum_coverage, :source_total_bytes, :artifact_total_bytes,
    :byte_accounting_result, :failures, :warnings,
])

function _parse_grok_failures(arr::Vector)::Vector{GrokOzempicFailure}
    return [GrokOzempicFailure(
        category = get(d, "category", ""),
        tensor = get(d, "tensor", nothing),
        message = get(d, "message", ""),
    ) for d in arr]
end

function _parse_grok_warnings(arr::Vector)::Vector{GrokOzempicWarning}
    return [GrokOzempicWarning(
        category = get(d, "category", ""),
        tensor = get(d, "tensor", nothing),
        message = get(d, "message", ""),
    ) for d in arr]
end

function load_grok_ozempic_bundle(path::AbstractString)::GrokOzempicBundle
    report_path = joinpath(path, "validation.report.json")

    if !isfile(report_path)
        error("Grok-ozempic bundle validation failed: validation.report.json not found at $(report_path)")
    end

    raw = JSON.parsefile(report_path)

    extra = Dict{String,Any}()
    for (k, v) in raw
        Symbol(k) in GROK_OZEMPIC_REPORT_FIELDS || (extra[k] = v)
    end

    failures = haskey(raw, "failures") ? _parse_grok_failures(raw["failures"]) : GrokOzempicFailure[]
    warnings = haskey(raw, "warnings") ? _parse_grok_warnings(raw["warnings"]) : GrokOzempicWarning[]

    report = GrokOzempicReport(
        status = get(raw, "status", "UNKNOWN"),
        source_tensor_count = get(raw, "source_tensor_count", 0),
        artifact_tensor_count = get(raw, "artifact_tensor_count", 0),
        router_count = get(raw, "router_count", 0),
        protected_router_violations = get(raw, "protected_router_violations", 0),
        protected_norm_violations = get(raw, "protected_norm_violations", 0),
        expert_association_count = get(raw, "expert_association_count", 0),
        unknown_unresolved_warning_count = get(raw, "unknown_unresolved_warning_count", 0),
        checksum_coverage = get(raw, "checksum_coverage", ""),
        source_total_bytes = get(raw, "source_total_bytes", 0),
        artifact_total_bytes = get(raw, "artifact_total_bytes", 0),
        byte_accounting_result = get(raw, "byte_accounting_result", ""),
        failures = failures,
        warnings = warnings,
        extra = extra,
    )

    return GrokOzempicBundle(report, path)
end

function validate_grok_ozempic_bundle(path::AbstractString)::Tuple{Bool, Vector{String}}
    errors = String[]
    report_path = joinpath(path, "validation.report.json")

    if !isfile(report_path)
        push!(errors, "validation.report.json not found at $(report_path)")
        return false, errors
    end

    try
        raw = JSON.parsefile(report_path)
        if !haskey(raw, "status")
            push!(errors, "validation.report.json missing required field: status")
        end
        if !haskey(raw, "source_tensor_count")
            push!(errors, "validation.report.json missing required field: source_tensor_count")
        end
    catch e
        push!(errors, "validation.report.json is not valid JSON: $(e)")
    end

    return isempty(errors), errors
end
