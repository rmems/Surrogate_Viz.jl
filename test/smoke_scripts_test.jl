# Smoke tests for the root-level entry-point scripts.
#
# These scripts are not part of the package and were, until recently, executed
# by nothing at all — no test and no CI job loaded them. That gap let a script
# ship with a load-time error that made it impossible to run (a TOML stdlib
# resolved by a UUID registered to no package, fixed in #51). The point of
# these tests is narrow but specific: prove each script still *loads*, and that
# loading it does not run its `main()`.
#
# Each script is included into a throwaway module so its constants and
# functions do not leak into the test session, and the active project is
# restored afterwards in case a script activates one at load time.

using Test
using Pkg

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

"""
    smoke_include(relpath) -> Module

Load `relpath` (relative to the repo root) into a fresh anonymous module and
return it. Restores the caller's active project afterwards.
"""
function smoke_include(relpath::AbstractString)
    path = joinpath(REPO_ROOT, relpath)
    isfile(path) || error("smoke_include: no such script $(path)")
    before = Base.active_project()
    sandbox = Module(Symbol("SmokeSandbox_", replace(relpath, r"[^A-Za-z0-9]" => "_")))
    # A module built at runtime has no `include` of its own — that is normally
    # created by the lowering of a `module ... end` block. Scripts that pull in
    # `src/Surrogate_Viz.jl` need it, so define one bound to this sandbox.
    Core.eval(sandbox, :(include(p) = Base.include(@__MODULE__, p)))
    try
        Base.include(sandbox, path)
    finally
        # A script that calls Pkg.activate at load time would otherwise leave
        # the rest of the suite pointed at the wrong project.
        if before !== nothing && Base.active_project() != before
            Pkg.activate(before; io = devnull)
        end
    end
    return sandbox
end

@testset "root scripts load without executing main()" begin
    # `PROGRAM_FILE` is the test runner, never the script under test, so the
    # `abspath(PROGRAM_FILE) == @__FILE__` guard in each script must be false
    # here. If a guard were missing, including the script would run its main()
    # and fail on missing data rather than returning a module.
    for script in ("import_corinth_runs.jl", "SAAQ_latent_discovery.jl")
        @testset "$script" begin
            # Assign outside @test so a load failure surfaces as one error on
            # this line, not as a cascade of `m not defined` on every assertion
            # below it.
            m = smoke_include(script)
            @test m isa Module

            # main() must be *defined* but not to have run. If it had run, the
            # include would have thrown before reaching here.
            @test isdefined(m, :main)
            @test getfield(m, :main) isa Function

            # The active project survived the include.
            @test Base.active_project() !== nothing
        end
    end
end

@testset "entry-point guards are present" begin
    # A guard that gets dropped in a refactor would silently re-arm the
    # execute-on-include behaviour, so assert on the source text too — the
    # load test above cannot distinguish "guard present" from "main() happened
    # to succeed with no arguments".
    for script in (
        "import_corinth_runs.jl",
        "SAAQ_latent_discovery.jl",
        "plot_latent_space.jl",
    )
        src = read(joinpath(REPO_ROOT, script), String)
        @test occursin("abspath(PROGRAM_FILE) == @__FILE__", src)
    end
end

@testset "scripts declare their own imports" begin
    # The compare scripts previously resolved stdlibs via
    # Base.require(Base.PkgId(Base.UUID(...))) with a hand-typed UUID; one of
    # them was wrong and the script could not load at all. Keep that idiom out
    # of the scripts these tests cover.
    for script in ("import_corinth_runs.jl", "SAAQ_latent_discovery.jl")
        src = read(joinpath(REPO_ROOT, script), String)
        @test !occursin("Base.PkgId", src)
    end
end
