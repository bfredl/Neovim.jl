module Neovim

using MsgPack
import MsgPack: pack, unpack
import Base: send

export NvimClient, nvim_connect, Buffer, Tabpage, Window

REQUEST = 0
RESPONSE = 1
NOTIFICATION = 2

type NvimClient
    # TODO: generalize to other transports
    stream::Base.Pipe
    channel_id::Int
    next_reqid::Int
    waiting::Dict{Int,RemoteRef}
    reader::Task

    function NvimClient(path::ByteString)
        stream = connect(path)
        c = new(stream, -1, 0, (Int=>RemoteRef)[])
        c.reader = @async readloop(c)
        c
    end
end

# this is probably not most efficient in the common case (no contention)
# but it's the simplest way to assure task-safety of reading from the stream
function readloop(c::NvimClient)
    while true
        msg = unpack(c.stream)
        #println(msg)
        kind = msg[1]::Int
        serial = msg[2]::Int
        if kind == RESPONSE
            ref = pop!(c.waiting, serial)
            put!(ref, (msg[3], msg[4]))
        end
    end
end

function nvim_connect(path::ByteString)
    c = NvimClient(path)
    c.channel_id, metadata = send(c, "vim_get_api_info", [])
    # doesn't work
    #if metadata != _metadata
    #    println("warning: possibly incompatible api metadata")
    #end
    return c
end

symbolize(val::Dict) = Dict{Symbol,Any}([(symbolize(k),symbolize(v)) for (k,v) in val])
symbolize(val::Vector{Uint8}) = symbol(bytestring(val))
symbolize(val::Vector) = [symbolize(v) for v in val]
symbolize(val) = val

function _get_metadata()
    data = readall(`nvim --api-info`)
    metadata = symbolize(unpack(data))
end

const _metadata = _get_metadata()
const _types = _metadata[:types]
const _functions = _metadata[:functions]

abstract NvimObject
# when upgrading to 0.4; use builtin typeconst
abstract _Typeid{N}

for (name, info) in _types
    id = info[:id]
    @eval begin 
        immutable $(name) <: NvimObject
            # TODO: use a fixarray or Uint64
            client::NvimClient
            hnd::Vector{Uint8}
        end
        typeid(::$(name)) = $id
        nvimobject(c, ::Type{_Typeid{$id}}, hnd) = $(name)(c, hnd)
    end
end

=={T<:NvimObject}(a::T,b::T) = a.hnd == b.hnd

#Not really module-interface clean, I know...
function MsgPack.pack(s, o::NvimObject)
    tid = typeid(o)
    MsgPack.pack(s, Ext(tid, o.hnd))
end

#on 0.4 this will be NvimObject
nvimobject(c, e::Ext) = nvimobject(c, _Typeid{int(e.typecode)}, e.data)

function send(c::NvimClient, meth, args)
    reqid = c.next_reqid
    c.next_reqid += 1
    # TODO: are these things cheap to alloc or should they be reused
    res = RemoteRef()
    c.waiting[reqid] = res
    meth = string(meth)

    msg = pack({0, reqid, meth, args})
    write(c.stream, msg)
    (err, res) = take!(res) #blocking
    # TODO: make these recoverable
    if err !== nothing
        error(string(meth, ": ", bytestring(err[2])))
    end
    #TODO: use METADATA to be type-stabler
    retconvert(c,res)
end

# FIXME: the elephant in the room (i.e. handle &encoding)
retconvert(c,val::Dict) = Dict{Any,Any}([(retconvert(c,k),retconvert(c,v)) for (k,v) in val])
retconvert(c,val::Vector{Uint8}) = bytestring(val)
retconvert(c,val::Vector) = [retconvert(c,v) for v in val]
retconvert(c,val::Ext) = nvimobject(c, val)
retconvert(c,val) = val

# a stagedfunction will probably be simpler and better
function build_function(f)
    name = f[:name]
    params = f[:parameters]

    parts = split(string(name), "_", 2)
    reciever = parts[1]
    shortname = symbol(parts[2])
    if shortname == "eval"; shortname = "vim_eval"; end

    body = Any[]
    args = Any[ symbol(string("a_",p[2])) for p in params]
    j_args = copy(args)
    #Very Magic
    if reciever == "vim"
        unshift!(j_args, :( c::NvimClient))
    else
        a_recv = args[1]
        j_args[1] = :( ($a_recv )::($(params[1][1])) )
        push!(body, :( c = ($a_recv).client ) )
    end

    #TODO: walk through args, make type-check julia-side

    #probaby is/should be a cleaner way...
    arglist = :( Any[] )
    append!(arglist.args, args)
    push!(body, :( send(c, $(Meta.quot(name)), $arglist)))

    #TODO: handle retvals typestable-wise

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

end
