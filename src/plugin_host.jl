start_host() = wait(nvim_child(HostHandler()).reader)

immutable HostHandler
    loaded_plugins::Set{String} # plugin file paths
    proc_callbacks::Dict{String, Function}
end

function HostHandler()
    HostHandler(Set{String}(), Dict{String, Function}())
end

# names/methods for invoked cmds/fns have the form:
#   <file path>:(command|function|autocmd):<procedure name>
function on_notify(::HostHandler, c, name, args)
    plugin_file, proc_type, proc_name = split(name, ':')
end

function on_request(h::HostHandler, c, serial, method, args)
    if method == "specs" # called on UpdateRemotePlugins
        reply_result(c, serial, get_specs(args...))
    else
        reply_result(c, serial, 42)
    end
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

    eval(plugin)

    fn_specs
end

# finds constructs that look like decorators (i.e. macrocall then function)
# and then adds the function name as the last argument to the macrocall
function decorate(file_name::String)
    ast = (open(readall, file_name) |> parse)::Expr

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
                push!(arg.args, fn_name)
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
