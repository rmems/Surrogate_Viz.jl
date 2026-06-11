# Zed / editor language-server entry point for this repo.
# Analyzes code with dev/ so Surrogate_Viz (path dep) and optional CUDA-backed
# code in src/cuda_backend.jl resolve for scripts and package sources. Launch
# from repo root, e.g.:
#   julia --project=@zed-julia --startup-file=no dev/runserver.jl
import Pkg
Pkg.activate(@__DIR__)

const LANGUAGE_SERVER_PKGID = Base.PkgId(Base.UUID("2b0e0bc5-e4fd-59b4-8912-456d1b03d8d7"), "LanguageServer")
if !any(pkg -> pkg.name == "LanguageServer", values(Pkg.dependencies()))
    Pkg.add("LanguageServer")
end

ls_mod = try
    Base.require(LANGUAGE_SERVER_PKGID)
catch
    Pkg.update()
    Base.require(LANGUAGE_SERVER_PKGID)
end

getfield(ls_mod, :runserver)(stdin, stdout, @__DIR__)
