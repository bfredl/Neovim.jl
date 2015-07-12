const REQUEST = 0
const RESPONSE = 1
const NOTIFICATION = 2

type NvimClient{S} <: NvimObject
    input::S #input to nvim
    output::S

    channel_id::Int
    next_reqid::Int
    waiting::Dict{Int,RemoteRef}
    reader::Task
    NvimClient(a,b,c,d,e) = new(a,b,c,d,e)
end

function NvimClient{S}(input::S, output::S, handler=DummyHandler())
    c = NvimClient{S}(input, output, -1, 0, Dict{Int,RemoteRef}())
    c.reader = @async readloop(c,handler)
    c.channel_id, metadata = send_request(c, "vim_get_api_info", [])
    #println("CONNECTED $(c.channel_id)"); flush(STDOUT)
    if symbolize(metadata) != _metadata
        println("warning: possibly incompatible api metadata")
    end
    c
end

# this is probably not most efficient in the common case (no contention)
# but it's the simplest way to assure task-safety of reading from the stream
function readloop(c::NvimClient, handler)
    while !eof(c.output)
        msg = unpack(c.output)
        kind = msg[1]::Int
        if kind == RESPONSE
            serial = msg[2]::Int
            ref = pop!(c.waiting, serial)
            put!(ref, (msg[3], msg[4]))
        elseif kind == NOTIFICATION
            name = bytestring(msg[2])
            args = retconvert(Any, c, msg[3])
            try
                on_notify(handler, c, name, args)
            catch err
                logerr(err, catch_backtrace(), "handler", "notification", name, args)
            end
        elseif kind == REQUEST
            serial = msg[2]::Int
            method = bytestring(msg[3])
            args = retconvert(Any, c, msg[4])
            try
                on_request(handler, c, serial, method, args)
            catch err
                reply_error(c, serial, "Caught Exception in request handler.")
                logerr(err, catch_backtrace(), "handler", "request", method, args)
            end
        end
        flush(STDERR)
    end
end

function logerr(e::Exception, bt, where, what, name, args)
    println(STDERR, "Caught Exception in $where for $what \"$name\" with arguments $args:")
    showerror(STDERR, e, bt)
    println(STDERR, "")
    flush(STDERR)
end

Base.wait(c::NvimClient) = wait(c.reader)

# we cannot use pack(stream, msg) as it's not synchronous
_send(c, msg) = (write(c.input, pack(msg)), flush(c.input))

function send_request(c::NvimClient, meth, args)
    reqid = c.next_reqid
    c.next_reqid += 1
    # TODO: are these things cheap to alloc or should they be reused
    res = RemoteRef()
    c.waiting[reqid] = res
    meth = string(meth)

    _send(c, Any[REQUEST, reqid, meth, args])
    (err, res) = take!(res) #blocking
    # TODO: make these recoverable
    if err !== nothing
        error(string(meth, ": ", bytestring(err[2])))
    end
    res
end

function reply_error(c, serial, err)
    _send(c, Any[RESPONSE, serial, err, nothing])
end

function reply_result(c, serial, res)
    _send(c, Any[RESPONSE, serial, nothing, res])
end

# when overriding these, note that this runs in the reader task,
# use @async/@spawn when doing anything long-running or blocking,
# including method calls to nvim
immutable DummyHandler; end
function on_notify(::DummyHandler, c, name, args)
    println("notification: $name $args")
end

function on_request(::DummyHandler, c, serial, name, args)
    println("WARNING: ignoring request $name $args, please override `on_request`")
    reply_error(c, serial, "Client cannot handle request, please override `on_request`")
end

