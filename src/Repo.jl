module Repo # Octo

import ..Backends
import ..AdapterBase
import ..Queryable: Structured, SubQuery, FromItem
import ..Raw
import ..Schema # Schema.validates
import ..Pretty: show

struct NeedsConnectError <: Exception
    msg
end

struct ExecuteResult
end

@enum RepoLogLevel::Int32 begin
    LogLevelDebugSQL = -1
    LogLevelInfo = 0
end

const current = Dict{Symbol, Union{Nothing, Module, RepoLogLevel}}(
    :adapter => nothing,
    :loader => nothing,
    :log_level => LogLevelInfo
)

const color_params = :yellow

current_loader() = current[:loader]
function current_adapter() # throw Repo.NeedsConnectError
    if current[:adapter] isa Nothing
        throw(NeedsConnectError("Needs to Repo.connect"))
    else
        current[:adapter]
    end
end

function set_log_level(level::RepoLogLevel)
    current[:log_level] = level
end

"""
    Repo.debug_sql(debug::Bool = true)
"""
function debug_sql(debug::Bool = true)
    current[:log_level] = debug ? LogLevelDebugSQL : LogLevelInfo
end

function print_debug_sql_params(io, params)
    printstyled(io, "   ")
    for (idx, x) in enumerate(params)
        printstyled(io, repr(x), color=color_params)
        length(params) != idx && printstyled(io, ", ")
    end
end

function print_debug_sql(stmt::Structured, params = nothing)
    if current[:log_level] <= LogLevelDebugSQL
        buf = IOBuffer()
        show(IOContext(buf, :color=>true), MIME"text/plain"(), stmt)
        !(params isa Nothing) && print_debug_sql_params(IOContext(buf, :color=>true), params)
        @info String(take!(buf))
    end
end

# Repo.connect
"""
    Repo.connect(; adapter::Module, kwargs...)
"""
function connect(; adapter::Module, kwargs...)
    sym = nameof(adapter)
    DatabaseID = getfield(AdapterBase.Database, Symbol(sym, :Database))
    AdapterBase.current[:database] = DatabaseID()

    current[:adapter] = adapter
    loader = Backends.backend(adapter)
    current[:loader] = loader

    if haskey(kwargs, :sink)
        Base.invokelatest(loader.sink, kwargs[:sink])
    end
    args = (:sink,)
    options = filter(kv -> !(kv.first in args), kwargs)

    Base.invokelatest(loader.db_connect; options...)
end

# Repo.disconnect
"""
    Repo.disconnect()
"""
function disconnect()
    loader = current_loader()
    disconnected = loader.db_disconnect()
    current[:adapter] = nothing
    current[:loader] = nothing
    disconnected
end


function _get_primary_key(M) # throw Schema.PrimaryKeyError
    Tname = Base.typename(M)
    info = Schema.tables[Tname]
    if haskey(info, :primary_key)
        a = current_adapter()
        table = a.from(M)
        primary_key = Symbol(info[:primary_key])
        a.Field(table, primary_key)
    else
        throw(Schema.PrimaryKeyError(""))
    end
end

function _get_primary_key_with(M, nt::NamedTuple) # throw Schema.PrimaryKeyError
    Tname = Base.typename(M)
    info = Schema.tables[Tname]
    if haskey(info, :primary_key)
        key = _get_primary_key(M)
        primary_key = Symbol(info[:primary_key])
        pk = getfield(nt, primary_key)
        (key, pk)
     else
        throw(Schema.PrimaryKeyError(""))
    end
end


# Repo.query

"""
    Repo.query(stmt::Structured)
"""
function query(stmt::Structured)
    a = current_adapter()
    sql = a.to_sql(stmt)
    print_debug_sql(stmt)
    loader = current_loader()
    loader.query(sql)
end

"""
    Repo.query(M::Type)
"""
function query(M::Type)
    a = current_adapter()
    table = a.from(M)
    query([a.SELECT * a.FROM table])
end

"""
    Repo.query(from::FromItem)
"""
function query(from::FromItem)
    query(from.__octo_model)
end

"""
    Repo.query(subquery::SubQuery)
"""
function query(subquery::SubQuery)
    query(subquery.__octo_query)
end

"""
    Repo.query(rawquery::Octo.Raw)
"""
function query(rawquery::Raw)
    query([rawquery])
end

### Repo.query - vals::Vector
"""
    Repo.query(stmt::Structured, vals::Vector)
"""
function query(stmt::Structured, vals::Vector) # throw Backends.UnsupportedError
    a = current_adapter()
    prepared = a.to_sql(stmt)
    print_debug_sql(stmt, vals)
    loader = current_loader()
    loader.query(prepared, vals)
end

### Repo.query - pk
"""
    Repo.query(M::Type, pk::Union{Int, String})
"""
function query(M::Type, pk::Union{Int, String}) # throw Schema.PrimaryKeyError
    a = current_adapter()
    table = a.from(M)
    key = _get_primary_key(M)
    query([a.SELECT * a.FROM table a.WHERE key == pk])
end

"""
    Repo.query(from::FromItem, pk::Union{Int, String})
"""
function query(from::FromItem, pk::Union{Int, String}) # throw Schema.PrimaryKeyError
    query(from.__octo_model, pk)
end

### Repo.query - pk_range
"""
    Repo.query(M::Type, pk_range::UnitRange{Int64})
"""
function query(M::Type, pk_range::UnitRange{Int64}) # throw Schema.PrimaryKeyError
    a = current_adapter()
    table = a.from(M)
    key = _get_primary_key(M)
    query([a.SELECT * a.FROM table a.WHERE key a.BETWEEN pk_range.start a.AND pk_range.stop])
end

"""
    Repo.query(from::FromItem, pk_range::UnitRange{Int64}
"""
function query(from::FromItem, pk_range::UnitRange{Int64}) # throw Schema.PrimaryKeyError
    query(from.__octo_model, pk_range)
end

### Repo.query - nt::NamedTuple
"""
    Repo.query(stmt::Structured, nt::NamedTuple)
"""
function query(stmt::Structured, nt::NamedTuple)
    a = current_adapter()
    v = vec(stmt)
    for (idx, kv) in enumerate(pairs(nt))
        key = a.Field(nothing, kv.first)
        push!(v, key == kv.second)
        idx != length(nt) && push!(v, a.AND)
    end
    query(v)
end

"""
    Repo.query(M::Type, nt::NamedTuple)
"""
function query(M::Type, nt::NamedTuple)
    a = current_adapter()
    table = a.from(M)
    v = [a.SELECT, *, a.FROM, table, a.WHERE]
    for (idx, kv) in enumerate(pairs(nt))
        key = Base.getproperty(table, kv.first)
        push!(v, key == kv.second)
        idx != length(nt) && push!(v, a.AND)
    end
    query(v)
end

"""
    Repo.query(from::FromItem, nt::NamedTuple)
"""
function query(from::FromItem, nt::NamedTuple)
    query(from.__octo_model, nt)
end

"""
    Repo.query(subquery::SubQuery, nt::NamedTuple)
"""
function query(subquery::SubQuery, nt::NamedTuple)
    query(subquery.__octo_query, nt)
end

"""
    Repo.query(rawquery::Octo.Raw, nt::NamedTuple)
"""
function query(rawquery::Raw, nt::NamedTuple)
    query([rawquery], nt)
end


# Repo.get
"""
    Repo.get(M::Type, pk::Union{Int, String})
"""
function get(M::Type, pk::Union{Int, String}) # throw Schema.PrimaryKeyError
    query(M, pk)
end

"""
    Repo.get(M::Type, pk_range::UnitRange{Int64})
"""
function get(M::Type, pk_range::UnitRange{Int64}) # throw Schema.PrimaryKeyError
    query(M, pk_range)
end

"""
    Repo.get(M::Type, nt::NamedTuple)
"""
function get(M::Type, nt::NamedTuple)
    query(M, nt)
end


# Repo.execute
"""
    Repo.execute(stmt::Structured)::ExecuteResult
"""
function execute(stmt::Structured)::ExecuteResult
    a = current_adapter()
    sql = a.to_sql(stmt)
    print_debug_sql(stmt)
    loader = current_loader()
    loader.execute(sql)
end

"""
    Repo.execute(stmt::Structured, vals::Vector)::ExecuteResult
"""
function execute(stmt::Structured, vals::Vector)::ExecuteResult
    a = current_adapter()
    prepared = a.to_sql(stmt)
    print_debug_sql(stmt, vals)
    loader = current_loader()
    loader.execute(prepared, vals)
end

"""
    Repo.execute(stmt::Structured, nts::Vector{<:NamedTuple})::ExecuteResult
"""
function execute(stmt::Structured, nts::Vector{<:NamedTuple})::ExecuteResult
    a = current_adapter()
    prepared = a.to_sql(stmt)
    print_debug_sql(stmt, nts)
    loader = current_loader()
    loader.execute(prepared, nts)
end

execute(raw::AdapterBase.Raw)::ExecuteResult                            = execute([raw])
execute(raw::AdapterBase.Raw, nt::NamedTuple)::ExecuteResult            = execute([raw], [nt])
execute(raw::AdapterBase.Raw, nts::Vector{<:NamedTuple})::ExecuteResult = execute([raw], nts)
execute(raw::AdapterBase.Raw, vals::Vector)::ExecuteResult              = execute([raw], vals)


# Repo.insert!
"""
    Repo.insert!(M::Type, nts::Vector{<:NamedTuple})::ExecuteResult
"""
function insert!(M::Type, nts::Vector{<:NamedTuple})::ExecuteResult
    if isempty(nts)
        ExecuteResult()
   else
        Schema.validates.(M, nts) # throw InvalidChangesetError
        a = current_adapter()
        table = a.from(M)
        nt = first(nts)
        fieldnames = a.Enclosed(collect(keys(nt)))
        execute([a.INSERT a.INTO table fieldnames a.VALUES a.placeholders(length(nt))], nts)
   end
end

"""
    Repo.insert!(M, nt::NamedTuple)::ExecuteResult
"""
function insert!(M, nt::NamedTuple)::ExecuteResult
    insert!(M, [nt])
end

"""
    Repo.insert!(M::Type, vals::Vector{<:Tuple})::ExecuteResult
"""
function insert!(M::Type, vals::Vector{<:Tuple})::ExecuteResult
    if isempty(vals)
        ExecuteResult()
   else
        a = current_adapter()
        table = a.from(M)
        execute([a.INSERT a.INTO table a.VALUES a.VectorOfTuples(vals)])
   end
end


# Repo.update!
"""
    Repo.update!(M::Type, nt::NamedTuple)::ExecuteResult
"""
function update!(M::Type, nt::NamedTuple)::ExecuteResult # throw Schema.PrimaryKeyError
    Schema.validates(M, nt) # throw InvalidChangesetError
    a = current_adapter()
    (key, pk) = _get_primary_key_with(M, nt)
    table = a.from(M)
    rest = filter(kv -> kv.first != key.name, pairs(nt))
    v = Any[a.UPDATE, table, a.SET]

    # tup[1] : idx
    # tup[2] : kv
    push!(v, tuple(map(tup -> a.Field(table, tup[2].first) == a.placeholder(tup[1]), enumerate(rest))...))

    push!(v, a.WHERE)
    push!(v, key == pk)
    execute(v, collect(values(rest)))
end


# Repo.delete!
"""
    Repo.delete!(M::Type, nt::NamedTuple)::ExecuteResult
"""
function delete!(M::Type, nt::NamedTuple)::ExecuteResult # throw Schema.PrimaryKeyError
    a = current_adapter()
    (key, pk) = _get_primary_key_with(M, nt)
    table = a.from(M)
    execute([a.DELETE a.FROM table a.WHERE key == pk])
end

"""
    Repo.delete!(M::Type, pk_range::UnitRange{Int64})::ExecuteResult
"""
function delete!(M::Type, pk_range::UnitRange{Int64})::ExecuteResult # throw Schema.PrimaryKeyError
    a = current_adapter()
    table = a.from(M)
    key = _get_primary_key(M)
    execute([a.DELETE a.FROM table a.WHERE key a.BETWEEN pk_range.start a.AND pk_range.stop])
end

function Base.show(io::IO, mime::MIME"text/plain", result::ExecuteResult)
end

end # module Octo.Repo
