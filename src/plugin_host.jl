start_host() = try wait(nvim_child(HostHandler())) end

immutable HostHandler
    specs::Dict{ByteString, Any} # plugin file paths
    proc_callbacks::Dict{ByteString, Function}
    HostHandler() = new(Dict{ByteString, Any}(), Dict{ByteString, Function}())
end

# names/methods for invoked cmds/fns have the form:
#   <file path>:(command|function|autocmd):<procedure name>
function on_notify(h::HostHandler, c, name::String, args::Vector{Any})
    proc = require_callback(h, name)

    if proc == nothing
        println(STDERR, "Callback for notification $name not defined.\n")
    end

    @async(try
        proc(c, args...)
    catch err
        logerr(err, catch_backtrace(), "callback", "notification", name, args)
    end)
end

function on_request(h::HostHandler, c, serial, method, args)
    if method == "specs" # called on UpdateRemotePlugins
        reply_result(c, serial, require_plugin(h, args...))
        println(STDERR, h)
    else
        proc = require_callback(h, method)

        if proc == nothing
            emsg = "Callback for request $method not defined."
            reply_error(c, serial, emsg)
            println(STDERR, "$emsg\n")
        end

        @async(try
            reply_result(c, serial, proc(c, args...))
        catch err
            reply_error(c, serial, "Exception in callback for request $method")
            logerr(err, catch_backtrace(), "callback", "request", method, args)
        end)
    end
end

function require_callback(h::HostHandler, name::ByteString)
    (plugin_file, proc_id) = split(name, ':', 2)
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
        require(filename)
    catch err
        println(STDERR, "Error while loading plugin " * filename)
        println(STDERR, err)
    end
    delete!(tls, :nvim_plugin_host)
    delete!(tls, :nvim_plugin_filename)
    specs
end


# called by result of "decorator" macros in plugin files
function plug(proc_type, name, handler, opt_args)
    conf = Dict{ByteString, Any}()
    conf["type"] = proc_type
    conf["name"] = name
    opts = Dict{ByteString, Any}()
    for (opt_k, opt_v) in opt_args
        opts[string(opt_k)] = opt_v
    end
    conf["opts"] = opts
    conf["sync"] = pop!(opts, "sync", 0)
    tls = task_local_storage()
    h = tls[:nvim_plugin_host]
    filename = tls[:nvim_plugin_filename]
    push!(h.specs[filename], conf)

    pattern = ""
    for arg in opt_args
        if arg[1] == "pattern"
            pattern = ":" * arg[2]
        end
    end

    proc_name = "$filename:$proc_type:$name$pattern"
    h.proc_callbacks[proc_name] = handler
end

macro command(args...)
    call_plug(:command, args...)
end

macro autocmd(args...)
    call_plug(:autocmd, args...)
end

macro fn(args...)
    call_plug(:function, args...)
end

#WIP
function call_plug(proc_type, args...)
    if length(opts) == 0
        return symbol("")
    end
    #if length(args)== 1 && args[1].head = :->
    #    opts, call = args[1].args
    #end

    handler = opts[end]
    fcall_args = {string(proc_type), string(name), string(handler)}
    for opt in opts[1:end-1]
        var, val = opt.args
        push!(fcall_args, Expr(:tuple, string(var), val))
    end

    Expr(:call, :plug, fcall_args...)
end

