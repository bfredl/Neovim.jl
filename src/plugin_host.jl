# TODO(smolck): Didn't have `catch;`, is this right?
start_host() = try wait(nvim_child(HostHandler())) catch; end

struct HostHandler
    specs::Dict{String, Any} # plugin file paths
    proc_callbacks::Dict{String, Function}
    HostHandler() = new(Dict{String, Any}(), Dict{String, Function}())
end

# names/methods for invoked cmds/fns have the form:
#   <file path>:(command|function|autocmd):<procedure name>
function on_notify(h::HostHandler, c, name::AbstractString, args::Vector{Any})
    proc = require_callback(h, name)

    if proc === nothing
        println(stderr, "Callback for notification $name not defined.\n")
    end

    @async try
        proc(c, args...)
    catch err
        logerr(err, catch_backtrace(), "callback", "notification", name, args)
    end
end

function on_request(h::HostHandler, c, serial, method, args)
    if method == "specs" # called on UpdateRemotePlugins
        reply_result(c, serial, require_plugin(h, args...))
        println(stderr, h)
    else
        proc = require_callback(h, method)

        if proc === nothing
            emsg = "Callback for request $method not defined."
            reply_error(c, serial, emsg)
            println(stderr, "$emsg\n")
        end

        @async try
            reply_result(c, serial, proc(c, args...))
        catch err
            logerr(err, catch_backtrace(), "callback", "request", method, args)
            reply_error(c, serial, "Exception in callback for request $method")
        end
    end
end

function require_callback(h::HostHandler, name::String)
    (plugin_file, proc_id) = split(name, ':',limit=2)
    require_plugin(h, plugin_file)
    get(h.proc_callbacks, name, nothing)
end

function require_plugin(h::HostHandler, filename)
    if haskey(h.specs, filename)
        return h.specs[filename]
    end
    h.specs[filename] = specs = Any[]
    tls = task_local_storage()
    tls[:nvim_plugin_host] = h
    tls[:nvim_plugin_filename] = filename
    try
        Base.include(Main, filename)
    catch err
        println(stderr, "Error while loading plugin $filename:")
        showerror(stderr, err, catch_backtrace())
        flush(stderr)
    end
    delete!(tls, :nvim_plugin_host)
    delete!(tls, :nvim_plugin_filename)
    specs
end


# called by result of "decorator" macros in plugin files
function plug(proc_type, name, handler, opt_args...)
    conf = Dict{String, Any}()
    conf["type"] = proc_type
    conf["name"] = name
    opts = Dict{String, Any}()
    for (opt_k, opt_v) in opt_args
        opts[opt_k] = opt_v
    end
    conf["opts"] = opts
    conf["sync"] = pop!(opts, "sync", 0)
    tls = task_local_storage()
    h = tls[:nvim_plugin_host]
    filename = tls[:nvim_plugin_filename]
    push!(h.specs[filename], conf)

    proc_name = "$filename:$proc_type:$name"
    if haskey(opts, "pattern")
        proc_name *= ":" * opts["pattern"]
    end
    h.proc_callbacks[proc_name] = handler
end

macro command(args...)
    call_plug(:command, args...)
end

macro commandsync(args...)
    call_plug(:command, args..., sync=true)
end

macro autocmd(args...)
    call_plug(:autocmd, args...)
end

macro autocmdsync(args...)
    call_plug(:autocmd, args..., sync=true)
end

macro fn(args...)
    call_plug(:function, args...)
end

macro fnsync(args...)
    call_plug(:function, args..., sync=true)
end

function fun(ex)
    if ex.head == :block && length(ex.args) == 2
        ex.args[2]
    else
        @assert ex.head == :function || ex.head == :(=)
        ex
    end
end

function call_plug(proc_type, args...; sync=false)
    if length(args) == 1 && args[1].head == :->
        # unwrap as line continuation
        args = args[1].args
    end
    @assert length(args) <= 2

    if length(args) == 2 && args[1].head == :call
        name = args[1].args[1]
        opts = args[1].args[2:end]
        handler = args[2]
    else
        if length(args) == 1
            opts = Any[]
        elseif args[1].head == :tuple
            opts = args[1].args
            args = args[2:end]
        elseif args[1].head == :(=)
            opts = Any[args[1]]
            args = args[2:end]
        else
            error("malformatted registration macro")
        end
        handler = fun(args[1])
        @assert handler.args[1].head == :call
        name = handler.args[1].args[1]
    end

    fcall_args = Any[string(proc_type), string(name), esc(handler)]
    for opt in opts
        var, val = opt.args
        push!(fcall_args, Expr(:tuple, string(var), val))
    end
    if sync
        push!(fcall_args, :(("sync", true)))
    end

    Expr(:call, :(Neovim.plug), fcall_args...)
end
