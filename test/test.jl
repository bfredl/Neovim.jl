# TODO: use --embed to make this a real test
using Neovim
c = nvim_connect(adress)
buf = send(c, :vim_get_buffers, [])[1]
@assert isa(buf,Buffer)
send(c, :buffer_set_line, {buf, 1, "some text"})
text = send(c, :buffer_get_line, {buf, 1})
@assert text == "some text"
