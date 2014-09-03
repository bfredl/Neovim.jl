using Msgpack
import Msgpack: pack, unpack
import Base: send

type NVClient
    # TODO: generalize to other transports
    stream::Base.Pipe
    reader::Task
    next_reqid::Int
end

function NVClient(path::ByteString)
    stream = connect(path)
    reader = @async while true
        println(unpack(stream))
    end
    NVClient(stream, reader, 0)
end

function send(c::NVClient, meth, args...)
    reqid = c.next_reqid
    c.next_reqid += 1
    write(c.stream, pack({0, reqid, meth, [args...]}))
end

function strictlytesting()
    c = NVClient("/tmp/n2")
    send(c,0) 
end

