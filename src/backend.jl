abstract type ComputeBackend end

struct CPUBackend <: ComputeBackend end
struct CUDABackend <: ComputeBackend end

const _CUDA_PKGID = Base.PkgId(Base.UUID("052768ef-5323-5732-b1bb-66c8b64840ba"), "CUDA")

function _cuda_module()
    return Base.require(_CUDA_PKGID)
end

function has_cuda()
    try
        cuda_mod = _cuda_module()
        return Base.invokelatest(getproperty(cuda_mod, :functional))
    catch e
        if e isa ArgumentError || e isa ErrorException || e isa LoadError
            return false
        end
        rethrow()
    end
end
