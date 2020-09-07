using Test
import Base: return_types

using Compat

import Distributed: RemoteChannel

using Neovim
import Neovim: get_buffers, set_line, get_line
import Neovim: vim_eval, command, get_var, set_var
import Neovim: on_notify, on_request
nvim, proc = Neovim.nvim_spawn()

# Test buffer
buf = get_buffers(nvim)[1]
@assert isa(buf, Buffer)
set_line(buf, 0, "some text")
text = get_line(buf, 0)
@assert text == "some text"

# test high-level buffer interface
buf = current_buffer(nvim)
@assert isa(buf, Buffer)
@assert buf[:] == ["some text"]
@assert buf[1] == "some text"

buf[:] = ["alpha", "beta", "gamma"]
@assert buf[:] == ["alpha", "beta", "gamma"]
@assert buf[1] == "alpha"
@assert buf[1:3] == ["alpha", "beta", "gamma"]
@assert buf[1:1] == ["alpha"]
@assert buf[end - 1:end] == ["beta", "gamma"]
@assert buf[1 + end - 1:end] == ["gamma"]
@assert buf[end - 1 + 1:1 + end - 1] == ["gamma"]
@assert buf[end - 1:2] == ["beta"]
@assert buf[end + 1 - 1] == "gamma"
@assert buf[1 + end - 1] == "gamma"
@assert buf[2:1] == []
@assert buf[1:0] == []

@test_throws BoundsError buf[0]
@test_throws BoundsError buf[-1]
@test_throws BoundsError buf[end + 1]
@test_throws BoundsError buf[-1:1]
@test_throws BoundsError buf[0:1]
@test_throws BoundsError buf[-1:0]
@test_throws BoundsError buf[end + 1:1]
@test_throws BoundsError buf[1:end + 1]
@test_throws BoundsError buf[1:1 + end]
@test_throws BoundsError buf[1 + end:1]
@test_throws BoundsError buf[end - 1:end + 1]
@test_throws BoundsError buf[end:end + 1]
@test_throws BoundsError buf[end + 1:end + 1]

@assert (buf[2] = "beta-ish") == "beta-ish"
@assert buf[:] == ["alpha", "beta-ish", "gamma"]
@assert (buf[end] = "gamma-ish") == "gamma-ish"
@assert buf[:] == ["alpha", "beta-ish", "gamma-ish"]
@assert (buf[2:3] = ["b", "c", "d"]) == ["b", "c", "d"]
@assert buf[:] == ["alpha", "b", "c", "d"]
@assert (buf[end - 1:end - 2] = ["boom"]) == ["boom"]
@assert buf[:] == ["alpha", "b", "boom", "c", "d"]
@assert (buf[end - 1:1 + end - 2] = ".") == "."
@assert buf[:] == ["alpha", "b", "boom", ".", "d"]

@test_throws BoundsError buf[0] = "twas"
@test_throws BoundsError buf[-1] = "brillyg"
@test_throws BoundsError buf[end + 1] = "and"
@test_throws BoundsError buf[-1:1] = "the"
@test_throws BoundsError buf[0:1] = "slythy"
@test_throws BoundsError buf[-1:0] = "toves"
@test_throws BoundsError buf[end + 1:1] = "did"
@test_throws BoundsError buf[1:end + 1] = "gyre"
@test_throws BoundsError buf[1:1 + end] = "and"
@test_throws BoundsError buf[1 + end:1] = "gymble"
@test_throws BoundsError buf[end - 1:end + 1] = "in"
@test_throws BoundsError buf[end:end + 1] = "the"
@test_throws BoundsError buf[end + 1:end + 1] = "wabe"

deleteat!(buf, 2)
@assert buf[:] == ["alpha", "boom", ".", "d"]
deleteat!(buf, 3:4)
@assert buf[:] == ["alpha", "boom"]

push!(buf, "the end")
@assert buf[:] == ["alpha", "boom", "the end"]
pushfirst!(buf, "stuff")
@assert buf[:] == ["stuff", "alpha", "boom", "the end"]
@assert length(buf) == 4

# test high-level cursor api
win = current_window(nvim)
cursor!(win, 1, 1)
@assert cursor(win) == (1, 1)
cursor!(win, 4, 2)
@assert cursor(win) == (4, 2)

# test eval
@assert vim_eval(nvim, "2+2") == 4

# test command and async behavior
command(nvim, "let g:test = []")
@sync for i in 1:5
    @async for j in 1:5
        command(nvim, "call add(g:test, [$i,$j])")
        if rand() > 0.5; sleep(0.001) end
    end
end

res = get_var(nvim, "test")
@assert length(res) == 25
for i in 1:5
    @assert all(indexin([[i,j] for j in 1:5], res) .> 0)
end

# test events
struct TestHandler
    r::RemoteChannel
end
on_notify(h::TestHandler, c, name, args) = put!(h.r, (name, args))
function on_request(h::TestHandler, c, serial, name, args)
    if name == "do_stuff"
        reply_result(c, serial, 10 * args[1] + args[2])
    end
end

# notification
ref = RemoteChannel()
nvim, proc = nvim_spawn(TestHandler(ref))
command(nvim, "call rpcnotify($(nvim.channel_id), 'mymethod', 10, 20)")
@assert take!(ref) == ("mymethod", Any[10, 20])

# request
@assert vim_eval(nvim, "100+rpcrequest($(nvim.channel_id), 'do_stuff', 2, 3)") == 123

# type stability of generated functions
# TODO(smolck): This doesn't pass now
# @assert return_types(Neovim.get_buffers, (NvimClient,)) == [Vector{Buffer}]

@assert return_types(Neovim.command, (NvimClient, String)) == [Nothing]
@assert return_types(Neovim.get_current_line, (NvimClient,)) == [String]
@assert return_types(Neovim.is_valid, (Tabpage,)) == [Bool]

# TODO(smolck): These don't pass now either
# @assert return_types(Neovim.get_height, (Window,)) == [Int]
# @assert return_types(Neovim.get_mark, (Buffer, String)) == [Tuple{Int,Int}]

# as ByteString isn't concrete anyway, this doesn't give that much really
# @assert return_types(Neovim.get_line_slice, (Buffer,Int,Int,Bool,Bool)) == [Vector{TypeVar(:_,None,ByteString)}]

# test host
hostdir = dirname(dirname(@__FILE__))
plugdir = joinpath(dirname(@__FILE__), "hosttest")

# fake initialization for :UpdateRemotePlugins
vimdir = mktempdir(cleanup=false)
nvimrc = joinpath(vimdir, "nvimrc")
open(f -> nothing, nvimrc,"w")
ENV["MYVIMRC"] = nvimrc
ENV["NEOVIM_JL_DEBUG"] = "templog"
println(vimdir)
ENV["NVIM_RPLUGIN_MANIFEST"] = vimdir * "/rplugin.vim"
ENV["NVIM_LOG_FILE"] = vimdir * "/.nvimlog"
rtp = "set rtp+=$hostdir,$plugdir"
juliap = "let g:julia_host_prog = '$(joinpath(Sys.BINDIR, "julia"))'"
cmd = `nvim -u $nvimrc -i NONE --cmd $rtp --cmd $juliap -c UpdateRemotePlugins -c q`
run(cmd)
run(`cat templog`)

try
    local ref = RemoteChannel()
    n, p = nvim_spawn(TestHandler(ref), cmd=`nvim -u $nvimrc -i NONE --cmd $rtp --cmd $juliap --embed --headless`)

    @assert vim_eval(n, "TestFun('a',3)") == "TestFun got a, 3"

    command(n, "call AsyncFun($(n.channel_id), {'alfa':1, 'omega':'theend'})")
    @assert take!(ref) == ("AsyncReply", Any[Dict("alfa" => 1, "omega" => "theend")])

    command(n, "new")
    b = current_buffer(n)
    b[1:5] = "line"
    command(n, "2,3JLCommand text")
    @assert b[:] == ["line","line","line","line","line","text"]
    @assert get_var(n, "therange") == [2,3]

# TODO: more specific test? (somewhere in there should be "KABOOM!")
    @test_throws ErrorException command(n, "Explode")

    set_var(n, "zinged", 5)
    command(n, "do User zing")
    @assert get_var(n, "zinged") == 6
    command(n, "do User yoink")
# shouldn't change
    @assert get_var(n, "zinged") == 6

    @assert vim_eval(n, "Global()") == 3
    @assert vim_eval(n, "Local()") == 37

finally
# for debugging tests:
    run(`cat templog`)
end
