# Generate low-level api from METADATA

# Types defined by the api
immutable NvimApiObject{N} <: NvimObject
    client::NvimClient
    # TODO: use a fixarray or Uint64
    hnd::Vector{Uint8}
end

function _get_metadata()
    data = readall(`nvim --api-info`)
    return symbolize(unpack(data))
end

symbolize(val::Dict) = Dict{Symbol,Any}([(symbolize(k),symbolize(v)) for (k,v) in val])
symbolize(val::Vector{Uint8}) = symbol(bytestring(val))
symbolize(val::ByteString) = symbol(val)
symbolize(val::Vector) = [symbolize(v) for v in val]
symbolize(val) = val

const _metadata = _get_metadata()
const _types = _metadata[:types]
const _functions = _metadata[:functions]

# will break if the api starts using overloading
const api_methods = [f[:name] => f for f in _functions]

const typemap = @compat Dict{Symbol,Type}(
    :Integer => Integer,
    :Boolean => Bool,
    :String => Union(ByteString, Vector{Uint8})
)

function parsetype(t::Symbol)
    components = split(rstrip(string(t), ')'), '(')
    top = symbol(components[1])
    params = length(components) > 1 ? split(components[2], ", ") : []
    (top, params)
end

function gettype(t::Symbol)
    top, params = parsetype(t)
    if haskey(typemap, top)
        typemap[top]
    elseif top == :ArrayOf
        tcontains = gettype(symbol(params[1]))
        if length(params) == 1
            if isa(tcontains, UnionType)
                tarr = Union([Array{t, 1} for t in tcontains.types]...)
            else
                tarr = Array{tcontains, 1}
            end
            Union(tarr, Array{None, 1})
        else
            @compat Tuple{fill(tcontains, int(params[2]))...}
        end
    else
        Any
    end
end

convertdict(val::Dict) = Dict{ByteString,Any}([(convertdict(k),convertdict(v)) for (k,v) in val])
convertdict(val::Union(ByteString, Vector{Uint8})) = bytestring(val)
convertdict(val::Vector) = [convertdict(v) for v in val]
convertdict(val) = val

function retconvert(c::NvimClient, t::Symbol, v=:void)
    ttop, tparams = parsetype(t)

    if ttop == :ArrayOf
        tcontains = symbol(tparams[1])
        if length(tparams) == 1
            map(x->retconvert(c, tcontains, x), v)
        else
            ntuple(i->retconvert(c, tcontains, v[i]), int(tparams[2]))
        end
    elseif ttop == :Array || ttop == :Boolean || ttop == :Integer
        v
    elseif ttop == :Dictionary
        convertdict(v)
    elseif ttop == :Object
        v
    elseif ttop == :String
        bytestring(v)
    elseif ttop == :void
        nothing
    else eval(ttop) <: NvimApiObject
        NvimApiObject(c, v)
    end
end

for (name, info) in _types
    id = info[:id]
    @eval begin
        typealias $(name) NvimApiObject{$id}
        typemap[$(Meta.quot(name))] = $name
    end
end

=={N}(a::NvimApiObject{N},b::NvimApiObject{N}) = a.hnd == b.hnd

NvimApiObject(c, e::Ext) = NvimApiObject{int(e.typecode)}(c, e.data)
#Not really module-interface clean, I know...
MsgPack.pack{N}(s, o::NvimApiObject{N}) = MsgPack.pack(s, Ext(N, o.hnd))
MsgPack.pack(s, t::Tuple) = MsgPack.pack(s, [v for v in t])

# a stagedfunction will probably be simpler and better
function build_function(f)
    name = f[:name]
    params = f[:parameters]
    tret = f[:return_type]

    parts = split(string(name), "_", 2)
    reciever = parts[1]
    shortname = symbol(parts[2])
    if shortname == :eval; shortname = :vim_eval; end

    body = Expr[]
    args = Symbol[symbol(string("a_",p[2])) for p in params]
    j_args = Expr[]

    for (i,p) in enumerate(params)
        #this is probably too restrictive sometimes,
        # use convert for some types (sequences)?
        t = gettype(p[1])
        push!(j_args, :( $(args[i])::($t) ))
    end

    if reciever == "vim"
        unshift!(j_args, :( c::NvimClient))
    else
        push!(body, :( c = ($(args[1])).client ) )
    end

    #when array constructor non-concatenating, we could drop the Any
    arglist = :( Any[] )
    append!(arglist.args, args)
    push!(body, :( res = send_request(c, $(Meta.quot(name)), $arglist)))

    push!(body, :( retconvert(c, $(Meta.quot(tret)), res) ))

    j_call = Expr(:call, shortname, j_args...)
    fun = Expr(:function, j_call, Expr(:block, body...) )
    #println(fun)
    fun
end

#TODO: maybe this should be in a submodule
# then one could do `importall Neovim.API`
for f in _functions
    eval(build_function(f))
end

