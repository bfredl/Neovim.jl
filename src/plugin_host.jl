start_host() = try wait(nvim_child(HostHandler()).reader) end

immutable HostHandler
    loaded_plugins::Set{String} # plugin file paths
    proc_callbacks::Dict{String, Function}
end

function HostHandler()
    HostHandler(Set{String}(), Dict{String, Function}())
end

# names/methods for invoked cmds/fns have the form:
#   <file path>:(command|function|autocmd):<procedure name>
function on_notify(h::HostHandler, c, name::String, args::Vector{Any})
    proc = require_plug(h, name)

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
        reply_result(c, serial, get_specs(args...))
    else
        proc = require_plug(h, method)

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

function require_plug(h::HostHandler, name::String)
    (plugin_file, proc_id) = split(name, ':', 2)

    if plugin_file ∉ h.loaded_plugins
        cbs = get_callbacks(plugin_file)
        merge!(h.proc_callbacks, cbs)
    end

    get(h.proc_callbacks, name, nothing)
end

function get_specs(plugin_file)
    plugin = nothing
    try
        plugin = decorate(plugin_file)
    end

    fn_specs = {}
    global plug(proc_type, name, handler, opt_args...) = begin
        conf = Dict{String, Any}()
        conf["type"] = proc_type
        conf["name"] = name
        opts = Dict{String, Any}()
        for (opt_k, opt_v) in opt_args
            opts[string(opt_k)] = opt_v
        end
        conf["opts"] = opts
        conf["sync"] = pop!(opts, "sync", 0)
        push!(fn_specs, conf)
    end

    try
        eval(plugin)
    catch err
        println(STDERR, "Error while loading plugin " * plugin_file)
        println(STDERR, err)
    end

    fn_specs
end

function get_callbacks(plugin_file)
    plugin = nothing
    try
        plugin = decorate(plugin_file)
    end

    proc_callbacks = Array((String, Expr), 0)
    global plug(proc_type, name, handler, opt_args...) = begin
        pattern = ""
        for arg in opt_args
            if arg[1] == "pattern"
                pattern = ":" * arg[2]
            end
        end

        proc_name = "$plugin_file:$proc_type:$name$pattern"
        push!(proc_callbacks, (proc_name, parse(handler)))
    end

    try
        eval(plugin)
    catch err
        println(STDERR, "Error while loading plugin " * plugin_file)
        println(STDERR, err)
    end

    extract_fns(x) = (x[1], eval(x[2]))
    Dict{String, Function}(map(extract_fns, proc_callbacks))
end

# finds constructs that look like decorators (i.e. macrocall then function)
# and then adds the function name as the last argument to the macrocall
function decorate(file_name::String)
    ast = (open(readall, file_name) |> parse)::Expr
    module_name = ast.args[2]

    q = Array(Expr, 0)
    candidate_fns = Array((Expr, Expr), 0)
    push!(q, ast)
    while length(q) > 0
        expr = shift!(q)
        for (i, arg) in enumerate(expr.args)
            if typeof(arg) != Expr continue end
            if arg.head == :macrocall && expr.args[i + 2].head == :function
                # `i + 2` to skip LineNumberNode
                fn_name = expr.args[i + 2].args[1].args[1]
                push!(arg.args, symbol("$module_name.$fn_name"))
            elseif arg.head == :macrocall && contains(string(arg.args[1]), "Neovim")
                deleteat!(expr.args, i)
                println(STDERR, "Bad decorator in " * file_name * ": " * string(arg))
            end
            push!(q, arg)
        end
    end
    ast
end

# called by result of "decorator" macros in plugin files
function plug(proc_type, name, handler, opts...) end

macro command(args...)
    call_plug(:command, args...)
end

macro autocmd(args...)
    call_plug(:autocmd, args...)
end

macro fn(args...)
    call_plug(:function, args...)
end

function call_plug(proc_type, name, opts...)
    if length(opts) == 0
        return symbol("")
    end

    handler = opts[end]
    fcall_args = {string(proc_type), string(name), string(handler)}
    for opt in opts[1:end-1]
        var, val = opt.args
        push!(fcall_args, Expr(:tuple, string(var), val))
    end

    Expr(:call, :plug, fcall_args...)
end
