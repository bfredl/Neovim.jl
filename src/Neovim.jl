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

for (name, info) in _types
    id = info[:id]
    #println(name, id)
end
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
        println(typeof(err))
        error("rpc error")
    end
    res
end

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
