abstract type ComputeBackend end

struct CPUBackend <: ComputeBackend end
struct CUDABackend <: ComputeBackend end

const _CUDA_PKGID = Base.PkgId(Base.UUID("052768ef-5323-5732-b1bb-66c8b64840ba"), "CUDA")

function has_cuda()
    try
        cuda_mod = Base.require(_CUDA_PKGID)
        return getproperty(cuda_mod, :functional)()
    catch e
        if e isa ArgumentError || e isa ErrorException || e isa LoadError
            return false
        end
        rethrow()
    end
end
