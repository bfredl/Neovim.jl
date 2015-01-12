using Neovim
nv, p  = nvim_spawn()
b = current_buffer(nv)
println(@nvcall get_buffers(nv))
println(@nvcall get_current_buffer(nv))
println(@nvcall line_count(b))
println(@nvcall get_line(b, 1))
println(@nvcall get_line_slice(b, 1, 1, true, true))
