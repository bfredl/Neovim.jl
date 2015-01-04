using Neovim
import Neovim: get_buffers, set_line, get_line, vim_eval, command, get_var
nvim = nvim_spawn()
buf = get_buffers(nvim)[1]
@assert isa(buf,Buffer)
set_line(buf, 1, "some text")
text = get_line(buf, 1)
@assert text == "some text"

@assert vim_eval(nvim, "2+2") == 4

command(nvim, "let g:test = []")
@sync for i in range(1,5)
    @async for j in range(1,5)
        command(nvim, "call add(g:test, [$i,$j])")
        if rand() > 0.5; sleep(0.001) end
    end
end

res = get_var(nvim, "test")
assert( length(res) == 25 )
for i in range(1,5)
    @assert all(indexin([[i,j] for j in range(1,5)], res) .> 0)
end

