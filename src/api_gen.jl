# Generate low-level api from METADATA

using MsgPack
import MsgPack: Extension, ExtensionType

# Types defined by the api
struct NvimApiObject{N} <: NvimObject
    client::NvimClient
    # TODO: use a fixarray or UInt64
    hnd::Vector{UInt8}
end

import Base.==
==(a::NvimApiObject{N}, b::NvimApiObject{N}) where {N} = a.hnd == b.hnd

NvimApiObject(c, e::Extension) = NvimApiObject{UInt8(e.type)}(c, e.data)

# Not really module-interface clean, I know...
# TODO(smolck): Was just s with Any type, is this right?
MsgPack.pack(s::IO, o::NvimApiObject{N}) where {N} = MsgPack.pack(s, Extension(N, o.hnd))

symbolize(val::Dict) = Dict{Symbol,Any}([(symbolize(k), symbolize(v)) for (k, v) in val])
symbolize(val::Vector{UInt8}) = Symbol(String(val))
symbolize(val::String) = Symbol(val)
symbolize(val::Vector) = [symbolize(v) for v in val]
symbolize(val) = val

function _get_metadata()
    data = Nothing
    try
        data = read(`nvim --api-info`, String)
    catch x
        if isa(x, Base.IOError)
            data = read("src/api-metadata", String)
        else
            rethrow()
        end
    end
    return symbolize(unpack(data))
end

const _metadata = _get_metadata()
const _types = _metadata[:types]
const _functions = _metadata[:functions]

# will break if the api starts using overloading
const api_methods = [f[:name] => f for f in _functions]

const Bytes = Union{String,Vector{UInt8}}
const typemap = Dict{Symbol,Type}(
    :Integer => Integer,
    :Boolean => Bool,
    :String => Bytes,
    :Array => Vector{Any},
    :Dictionary => Dict,
    :Object => Any,
    :void => Nothing,
)

for (name, info) in _types
    id = info[:id]
    @eval begin
        const $(name) = NvimApiObject{$id}
        # typealias $(name) NvimApiObject{$id}
        typemap[$(Meta.quot(name))] = $name
    end
end

function parsetype(t::Symbol)
    components = split(rstrip(string(t), ')'), '(')
    top = Symbol(components[1])
    params = length(components) > 1 ? split(components[2], ", ") : []
    (top, params)
end

function gettype(t::Symbol)
    top, params = parsetype(t)
    if haskey(typemap, top)
        typemap[top]
    elseif top == :ArrayOf
        tcontains = gettype(Symbol(params[1]))
        if length(params) == 1
            Vector{tcontains}
        else
            Tuple{fill(tcontains, parse(Int, params[2]))...}
        end
    else
        Any
    end
end

# fake covariant Vectors
checkarg(::Type{Vector{T}}, val::Vector{T}) where {T} = val
checkarg(::Type{Vector{T}}, val::Vector) where {T} = convert(Vector{T}, val)

# I'm pretty sure julia somehow can express subdiagnal dispatch,
# but implement the cases manually for now
checkarg(::Type{Vector{Bytes}}, val::Vector{T}) where {T <: Bytes} = val
checkarg(::Type{Vector{Integer}}, val::Vector{T}) where {T <: Integer} = val

# this must be specialcased though
checkarg(::Type{Vector{Integer}}, val::Vector{UInt8}) = Int[val...]

# tuples are covariant, so no problem
checkarg(::Type{Vector{T}}, val::(Tuple{Vararg{T}})) where {T} = [val...]

retconvert(typ::Union{Type{Any},Type{Bytes}}, c, val::Union{String,Vector{UInt8}}) =
    String(val)

# needed for disambiguation
retconvert(typ::Type{Any}, c, val::Vector{UInt8}) = String(val)
retconvert(typ::Union{Type{Any},Type{Bool}}, c, val::Bool) = val

# this assumes the current unpack implementation in MsgPack,
# where all int types get promoted to 64 bit
retconvert(typ::Union{Type{Any},Type{Integer}}, c, val::Int64) = val
retconvert(typ::Union{Type{Any},Type{Nothing}}, c, val::Nothing) = nothing
retconvert(typ::Union{Type{Any},Type{Dict}}, c, val::Dict) =
    Dict{String,Any}([(String(k), retconvert(Any, c, v)) for (k, v) in val])

# we assume Msgpack only generates untyped arrays
retconvert(typ::Type{Vector{T}}, c, val::Vector) where {T} =
    [retconvert(T, c, v) for v in val]
retconvert(typ::Type{Any}, c, val::Vector) = Any[retconvert(Any, c, v) for v in val]

# this is not really strict enough
# retconvert{T<:Tuple}(typ::Type{T}, c, val::Vector) = tuple(val...)::T
# handle the only case, 2-tuples, manually for now
retconvert(::Type{Tuple{T,U}}, c, val::Vector) where {T,U} =
    (retconvert(T, c, val[1]), retconvert(U, c, val[2]))

retconvert(typ::Type{NvimApiObject{N}}, c, val::Extension) where {N} = NvimApiObject(c, val)::NvimApiObject{N}

retconvert(typ::Type{T}, c, val::T) where {T} = val

# a stagedfunction will probably be simpler and better
function build_function(f)
    name = f[:name]
    params = f[:parameters]
    tret = f[:return_type]

    parts = split(string(name), "_"; limit=2)
    receiver = parts[1]
    shortname = Symbol(parts[2])
    if shortname == :eval
        shortname = :vim_eval
    end

    body = Expr[]
    args = Symbol[Symbol(string("a_", p[2])) for p in params]
    j_args = Expr[]

    if length(args) != 0
        for (i, p) in enumerate(params)
            # this is probably too restrictive sometimes,
            # use convert for some types (sequences)?
            t = gettype(p[1])
            # if type is an array
            # we will allow any Vector argument
            # and dynamically check if not a subtype
            erased = t
            if t <: Vector
                erased = Union{Vector,Tuple{Vararg{eltype(t)}}}
                push!(body, :($(args[i]) = checkarg($t, $(args[i]))))
            end
            push!(j_args, :($(args[i])::($erased)))
        end
    end

    if length(j_args) == 0 || receiver == "vim"
        pushfirst!(j_args, :(c::NvimClient))
    else
        pushfirst!(body, :(c = ($(args[1])).client))
    end

    # when array constructor non-concatenating, we could drop the Any
    arglist = :(Any[])
    append!(arglist.args, args)
    push!(body, :(res = send_request(c, $(Meta.quot(name)), $arglist)))

    # "representative" type, not neccessarily the one
    # retconvert will assert
    typ = gettype(tret)
    push!(body, :(retconvert($typ, c, res)))

    j_call = Expr(:call, shortname, j_args...)
    fun = Expr(:function, j_call, Expr(:block, body...))
    fun
end

# TODO: maybe this should be in a submodule
# then one could do `importall Neovim.API`
for f in _functions
    eval(build_function(f))
end
