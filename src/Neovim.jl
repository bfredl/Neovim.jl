module Neovim

using Msgpack
import Msgpack: pack, unpack
import Base: send

REQUEST = 0
RESPONSE = 1
NOTIFICATION = 2

type NVClient
    # TODO: generalize to other transports
    stream::Base.Pipe
    channel_id::Int
    next_reqid::Int
    waiting::Dict{Int,RemoteRef}
    reader::Task

    function NVClient(path::ByteString)
        stream = connect(path)
        c = new(stream, -1, 0, (Int=>RemoteRef)[])
        c.reader = @async readloop(c)
        initialize(c)
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

function initialize(c)
    c.channel_id, metadata = send(c, 0)
    metadata = unpack(metadata)
    println(metadata)
end

function send(c::NVClient, meth, args...)
    reqid = c.next_reqid
    c.next_reqid += 1
    # TODO: are these things cheap to alloc or should they be reused
    res = RemoteRef()
    c.waiting[reqid] = res
    write(c.stream, pack({0, reqid, meth, [args...]}))
    (err, res) = take!(res) #blocking
    # TODO: make these recoverable
    if err !== nothing
        println(typeof(err))
        error("rpc error")
    end
    res
end

end
