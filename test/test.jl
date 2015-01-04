# TODO: use --embed to make this a real test
using Neovim
import Neovim: get_buffers, set_line, get_line
c = nvim_connect(adress)
buf = get_buffers(c)[1]
@assert isa(buf,Buffer)
set_line(buf, 1, "some text")
text = get_line(buf, 1)
@assert text == "some text"
