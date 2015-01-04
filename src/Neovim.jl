module Neovim

using MsgPack
import MsgPack: pack, unpack
import Base: send

REQUEST = 0
RESPONSE = 1
NOTIFICATION = 2

immutable NVHandle{T}
    hnd::Int
end
pack(s,h::NVHandle) = pack(s,hnd)

type NVClient
    # TODO: generalize to other transports
    stream::Base.Pipe
    channel_id::Int
    next_reqid::Int
    waiting::Dict{Int,RemoteRef}
    reader::Task
    rettypes::Dict{Symbol,Symbol}
    classes::Set{Symbol}

    function NVClient(path::ByteString)
        stream = connect(path)
        c = new(stream, -1, 0, (Int=>RemoteRef)[])
        c.reader = @async readloop(c)
        c
    end
end

# this is probably not most efficient in the common case (no contention)
function readloop(c::NVClient)
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

function neovim_connect(path::ByteString)
    c = NVClient(path)
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
            hnd::Vector{Uint8}
        end
        typeid(::$(name)) = $id
        nvimobject(::Type{_Typeid{$id}}, hnd) = $(name)(hnd)
    end
end

=={T<:NvimObject}(a::T,b::T) = a.hnd == b.hnd

#Not really module-interface clean, I know...
function MsgPack.pack(s, o::NvimObject)
    tid = typeid(o)
    MsgPack.pack(s, Ext(tid, o.hnd))
end

Base.convert(::Type{NvimObject}, e::Ext) = nvimobject(_Typeid{int(e.typecode)}, e.data)

for f in _functions
    name = f[:name]
    shortname = symbol(split(string(name), "_", 2)[2])
    if shortname == "eval"; shortname = "vim_eval"; end
    #println(name,shortname)
end


function send(c::NVClient, meth, args)
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
        println(typeof(err)) #FIXME
        error("rpc error")
    end
    #TODO: use METADATA to be type-stabler
    retconvert(res)
end

# FIXME: the elephant in the room (i.e. handle &encoding)
retconvert(val::Dict) = Dict{Any,Any}([(retconvert(k),retconvert(v)) for (k,v) in val])
retconvert(val::Vector{Uint8}) = bytestring(val)
retconvert(val::Vector) = [retconvert(v) for v in val]
retconvert(val::Ext) = convert(NvimObject, val)
retconvert(val) = val

# for testing, we should generate typesafe wrappers
function nvcall(c::NVClient, meth::Symbol, args...)
    packargs = Any[]
    for a in args
        if isa(a,NVHandle)
            a = a.hnd
        end
        push!(packargs, a)
    end
    res = send(c, bytestring(meth), packargs)
    res_type = c.rettypes[meth]
    if res_type in c.classes
        NVHandle{restype}(res)
    else #FIXME: strings
        res
    end
end

end
