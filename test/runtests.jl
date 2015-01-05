using Neovim
import Neovim: get_buffers, set_line, get_line, vim_eval, command, get_var
import Neovim: on_notify, on_request
nvim, proc = nvim_spawn()

#test buffer
buf = get_buffers(nvim)[1]
@assert isa(buf,Buffer)
set_line(buf, 1, "some text")
text = get_line(buf, 1)
@assert text == "some text"

#test eval
@assert vim_eval(nvim, "2+2") == 4

#test command and async behavior
command(nvim, "let g:test = []")
@sync for i in range(1,5)
    @async for j in range(1,5)
        command(nvim, "call add(g:test, [$i,$j])")
        if rand() > 0.5; sleep(0.001) end
    end
end

res = get_var(nvim, "test")
@assert length(res) == 25
for i in range(1,5)
    @assert all(indexin([[i,j] for j in range(1,5)], res) .> 0)
end

#test events
immutable TestHandler
    r::RemoteRef
end
on_notify(h::TestHandler, c, name, args) = put!(h.r, (name, args))
function on_request(h::TestHandler, c, serial, name, args)
    if name == "do_stuff"
        reply_result(c, serial, 10*args[1]+args[2])
    end
end

#notification
ref = RemoteRef()
nvim, proc = nvim_spawn(TestHandler(ref))
command(nvim, "call rpcnotify($(nvim.channel_id), 'mymethod', 10, 20)")
@assert take!(ref) == ("mymethod", {10, 20})

#request
@assert vim_eval(nvim, "100+rpcrequest($(nvim.channel_id), 'do_stuff', 2, 3)") == 123

