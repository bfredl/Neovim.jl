module Neovim

using Compat
using MsgPack
import MsgPack: pack, unpack

export NvimClient, nvim_connect, nvim_spawn, nvim_child
export Buffer, Tabpage, Window
export reply_result, reply_error

include("client.jl")
include("api_gen.jl")
include("interface.jl")

# too inconvenient api to supply handler here?
function nvim_connect(path::ByteString, args...)
    s = connect(path)
    NvimClient(s, s, args...)
end

function nvim_spawn(args...)
    output, input, proc = readandwrite(`nvim --embed`)
    (NvimClient(input, output, args...), proc)
end

function nvim_child(args...)
    # make stdio private. Reversed since from nvim's perspective
    input, output = STDOUT, STDIN
    debug = open("NEOVIM_JL_DEBUG","w") # TODO: make env var
    redirect_stdout(debug)
    redirect_stderr(debug)
    redirect_stdin()
    NvimClient(input, output, args...)
end

end
