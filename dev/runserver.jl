# Zed / editor language-server entry point for this repo.
# Analyzes code with dev/ so Surrogate_Viz (path dep) and CUDA resolve for
# scripts/ and ext/CUDABackendExt.jl. Launch from repo root, e.g.:
#   julia --project=@zed-julia --startup-file=no dev/runserver.jl
import Pkg
import UUIDs

ls_uuid = UUIDs.UUID("2b0e0bc5-e4fd-59b4-8912-456d1b03d8d7")
if !haskey(Pkg.dependencies(), ls_uuid)
    Pkg.add(Pkg.PackageSpec(uuid=ls_uuid))
end

try
    @eval using LanguageServer
catch
    Pkg.update()
    @eval using LanguageServer
end

using LanguageServer
runserver(stdin, stdout, @__DIR__)
