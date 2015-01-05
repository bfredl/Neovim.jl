module Neovim

using MsgPack
import MsgPack: pack, unpack

export NvimClient, nvim_connect, nvim_spawn, nvim_child
export Buffer, Tabpage, Window
export reply_result, reply_error

const REQUEST = 0
const RESPONSE = 1
const NOTIFICATION = 2

type NvimClient{S}
    input::S #input to nvim
    output::S

    channel_id::Int
    next_reqid::Int
    waiting::Dict{Int,RemoteRef}
    reader::Task
    NvimClient(a,b,c,d,e) = new(a,b,c,d,e)
end

function NvimClient{S}(input::S, output::S, handler=DummyHandler())
    c = NvimClient{S}(input, output, -1, 0, (Int=>RemoteRef)[])
    c.reader = @async readloop(c,handler)
    c.channel_id, metadata = send_request(c, "vim_get_api_info", [])
    #println("CONNECTED $(c.channel_id)"); flush(STDOUT)
    if symbolize(metadata) != _metadata
        println("warning: possibly incompatible api metadata")
    end
    c
end

# too inconvenient api to supply handler here?
function nvim_connect(path::ByteString, args...)
    s = connect(path)
    NvimClient(s, s, args...)
end

function nvim_spawn(args...)
    output, input, proc = readandwrite(`nvim --embed`)
    (NvimClient(input, output, args...), proc)
end

function nvim_child(args...)
    # make stdio private. Reversed since from nvim's perspective
    input, output = STDOUT, STDIN
    debug = open("NEOVIM_JL_DEBUG","w") # TODO: make env var
    redirect_stdout(debug)
    redirect_stderr(debug)
    redirect_stdin()
    NvimClient(input, output, args...)
end

# this is probably not most efficient in the common case (no contention)
# but it's the simplest way to assure task-safety of reading from the stream
function readloop(c::NvimClient, handler)
    while true
        msg = unpack(c.output)
        kind = msg[1]::Int
        if kind == RESPONSE
            serial = msg[2]::Int
            ref = pop!(c.waiting, serial)
            put!(ref, (msg[3], msg[4]))
        elseif kind == NOTIFICATION
            try
                on_notify(handler, c, bytestring(msg[2]), retconvert(c,msg[3]))
            catch err
                println("Excetion caught in notification handler")
                println(err)
            end
        elseif kind == REQUEST
            serial = msg[2]::Int
            try
                on_request(handler, c, serial, bytestring(msg[3]), retconvert(c,msg[4]))
            catch err
                println("Excetion caught in request handler")
                println(err)
            end
        end
    end
end

Base.wait(c::NvimClient) = wait(c.reader)

# we cannot use pack(stream, msg) as it's not synchronous
_send(c, msg) = (write(c.input, pack(msg)), flush(c.input))

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

function reply_error(c, serial, err)
    _send(c, {RESPONSE, serial, err, nothing}) 
end

function reply_result(c, serial, res)
    _send(c, {RESPONSE, serial, nothing, res})
end

symbolize(val::Dict) = Dict{Symbol,Any}([(symbolize(k),symbolize(v)) for (k,v) in val])
symbolize(val::Vector{Uint8}) = symbol(bytestring(val))
symbolize(val::ByteString) = symbol(val)
symbolize(val::Vector) = [symbolize(v) for v in val]
symbolize(val) = val

function _get_metadata()
    data = readall(`nvim --api-info`)
    return symbolize(unpack(data))
end

const _metadata = _get_metadata()
const _types = _metadata[:types]
const _functions = _metadata[:functions]

# will break if the api starts using overloading
const api_methods = [f[:name] => f for f in _functions]

const typemap = (Symbol=>Type)[
    :Integer => Integer,
    :Boolean => Bool,
    :String => Union(ByteString, Vector{Uint8}),
]

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
        typemap[$(Meta.quot(name))] = $name
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

function send_request(c::NvimClient, meth, args)
    reqid = c.next_reqid
    c.next_reqid += 1
    # TODO: are these things cheap to alloc or should they be reused
    res = RemoteRef()
    c.waiting[reqid] = res
    meth = string(meth)

    _send(c, {REQUEST, reqid, meth, args})
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
    if shortname == :eval; shortname = :vim_eval; end

    body = Any[]
    args = Any[ symbol(string("a_",p[2])) for p in params]
    j_args = Any[]

    for (i,p) in enumerate(params)
        #this is probably too restrictive sometimes,
        # use convert for some types (sequences)?
        t = get(typemap, p[1], Any)
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
    push!(body, :( send_request(c, $(Meta.quot(name)), $arglist)))

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
