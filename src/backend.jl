abstract type ComputeBackend end

struct CPUBackend <: ComputeBackend end
struct CUDABackend <: ComputeBackend end

function has_cuda()
    try
        @eval using CUDA
        return CUDA.functional()
    catch e
        if e isa ArgumentError || e isa ErrorException || e isa LoadError
            return false
        end
        rethrow()
    end
end