module test_stdlib_libdl

using Test
using Libdl

libllvm_paths = filter(Libdl.dllist()) do lib
    occursin("LLVM", basename(lib))
end
@test basename(first(libllvm_paths)) == "libLLVM.dylib"

end # module test_stdlib_libdl
