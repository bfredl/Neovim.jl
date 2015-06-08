# Generate low-level api from METADATA

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
    :String => Union(ByteString, Vector{Uint8}),
    :ArrayOf_Integer => Array{Int, 1}
)

function maptype(s::Symbol)
    arrayof = match(Regex("^ArrayOf\\((\\w+),"), string(s))
    if arrayof != nothing
        s = symbol("ArrayOf_" * arrayof.captures[1])
    end

    get(typemap, s, Any)
end

# Types defined by the api
immutable NvimApiObject{N} <: NvimObject
    client::NvimClient
    # TODO: use a fixarray or Uint64
    hnd::Vector{Uint8}
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
function MsgPack.pack{N}(s, o::NvimApiObject{N})
    MsgPack.pack(s, Ext(N, o.hnd))
end


# FIXME: the elephant in the room (i.e. handle &encoding)
retconvert(c,val::Dict) = Dict{Any,Any}([(retconvert(c,k),retconvert(c,v)) for (k,v) in val])
retconvert(c,val::Vector{Uint8}) = bytestring(val)
retconvert(c,val::Vector) = [retconvert(c,v) for v in val]
retconvert(c,val::Ext) = NvimApiObject(c, val)
retconvert(c,val) = val


# a stagedfunction will probably be simpler and better
function build_function(f)
    name = f[:name]
    params = f[:parameters]

    parts = split(string(name), "_", 2)
    reciever = parts[1]
    shortname = symbol(parts[2])
    if shortname == :eval; shortname = :vim_eval; end

    body = Any[]
    args = Any[symbol(string("a_",p[2])) for p in params]
    j_args = Any[]

    for (i,p) in enumerate(params)
        #this is probably too restrictive sometimes,
        # use convert for some types (sequences)?
        t = maptype(p[1])
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

    #TODO: handle retvals typestable-wise
    push!(body, :( retconvert(c, res) ))

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

