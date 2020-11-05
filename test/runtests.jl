using Jive
ignores = Set()
push!(ignores, "adapters/postgresql/copy_test")
runtests(@__DIR__, skip=collect(ignores))
