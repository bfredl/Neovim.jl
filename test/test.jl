using Neovim
import Neovim: get_buffers, set_line, get_line
nvim = nvim_spawn()
buf = get_buffers(nvim)[1]
@assert isa(buf,Buffer)
set_line(buf, 1, "some text")
text = get_line(buf, 1)
@assert text == "some text"
