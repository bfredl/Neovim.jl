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
    h.specs[filename] = Any[]
    tls = task_local_storage()
    try
        require(filename)
        add_specs!(h, filename, get_specs(tls[:plugin_module]))
    catch err
        println(STDERR, "Error while loading plugin " * filename)
        println(STDERR, err)
    end
    h.specs[filename]
end

macro plugin()
    :(task_local_storage()[:plugin_module] = current_module())
end

const cmd_types = Set([:Command, :Autocmd, :Function])
function get_specs(plugin::Module)
    plugin_specs = []

    if !isdefined(plugin, :META)
        return plugin_cmds
    end

    for f in filter(k->isa(k, Function), keys(plugin.META))
        fdocs = Base.Markdown.plain(Base.doc(f))
        spec_str = split(fdocs, '\n', 2)[1]
        try
            spec = parse(spec_str)
            if spec.head == :call && spec.args[1] in cmd_types
                push!(plugin_specs, (f, spec))
            end
        end
    end

    return plugin_specs
end

function add_specs!(h::HostHandler, filename, specs)
    for spec in specs
        handler, def = spec
        proc_type = lowercase(string(def.args[1]))
        proc_name = string(def.args[2])
        pattern = ""
        conf = Dict{ByteString, Any}()
        conf["type"] = proc_type
        conf["name"] = proc_name
        opts = Dict{ByteString, Any}()
        for opt in def.args[3:end]
            opt_k, opt_v = opt.args
            opts[string(opt_k)] = opt_v
            if opt_k == :pattern
                pattern = ":" * opt_v
            end
        end
        conf["opts"] = opts
        conf["sync"] = pop!(opts, "sync", false)

        push!(h.specs[filename], conf)
        proc_id = "$filename:$proc_type:$proc_name$pattern"
        h.proc_callbacks[proc_id] = handler
    end
end
