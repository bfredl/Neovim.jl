using Neovim
import Neovim: on_notify, on_request, get_buffers, set_line
#test events
struct ChildHandler
end
on_notify(h::ChildHandler, c, name, args) = (println("$name $args"), flush(stdout))
function on_request(h::ChildHandler, c, serial, name, args)
    if name == "run_julia"
        code = args[1]
        reply_result(c, serial, eval(code))
    end
end

nvim = nvim_child(ChildHandler())
buf = get_buffers(nvim)[1]
@assert isa(buf,Buffer)
set_line(buf, 1, "some text")

wait(nvim) #wait for request from nvim
