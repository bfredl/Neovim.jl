# mostly a proof-of-concept (more explicitly: a terrible hack) for the moment
# to activate, include() this file at the normal (LineEdit) REPL
# Then, at any time, press Ctrl-O to edit in normal mode.
# To be able to execute code and search history etc, going back to insert mode is neccesary.
# For the moment, the first keypress after going to insert mode disappears sometimes.
# import Base: LineEdit, REPL
import REPL
import REPL.LineEdit

include("Neovim.jl")

# using Neovim
# import Neovim: get_cursor, set_cursor, command, input

mutable struct NvimReplState
    active::Bool
    nv::Neovim.NvimClient
    s::LineEdit.MIState
    rbuf::IOBuffer
    function NvimReplState()
        state = new(false)
        state.nv = Neovim.nvim_spawn(state)
        state
    end
end


function Neovim.on_notify(s::NvimReplState, nv, name, args)
    @async begin
        update_screen()
        if name == "update"
            #done
        elseif name == "insert" 
            s.active = false
        end
    end
end

const rstate = NvimReplState()
const channel = rstate.nv.channel_id

Neovim.command(rstate.nv, "au CursorMoved,TextChanged * call rpcnotify($channel, 'update')")
Neovim.command(rstate.nv, "au InsertEnter * call rpcnotify($channel, 'insert')")
Neovim.command(rstate.nv, "set ft=julia")


const nvim_keymap = Dict(
    "^O" => function (s,repl,c)
        ps = LineEdit.state(s, LineEdit.mode(s))
        nvim_normal(ps.terminal,s,repl)
    end
)

function update_screen()
    if !rstate.active
        return
    end
    nv = rstate.nv
    #FIXME: this is a terrible hack, use abstract_ui later
    code = current_buffer(nv)[:]
    curline, curpos = get_cursor(current_window(nv))
    truncate(rstate.rbuf, 0)
    write(rstate.rbuf, join(code, "\n"))
    cpos = curpos
    for i in 1:(curline-1)
        cpos += length(code[i])+1
    end
    seek(rstate.rbuf, cpos)
    LineEdit.refresh_line(rstate.s)
end

function nvim_normal(term, s, repl)
    rstate.s = s
    rstate.rbuf = rbuf = LineEdit.buffer(s)
    nv = rstate.nv

    buf_pos = position(rbuf)
    seek(rbuf, 0)
    cur_col = buf_pos
    lines = ByteString[]
    more = true
    input(nv, "\033")
    cursor = [0,0]
    while more
        line = readline(rbuf)
        if length(line) > 0 && line[end] == '\n'
            line = line[1:end-1]
        else
            more = false
        end
        push!(lines, line)
        if 0 <= cur_col < length(line)+1
            cursor = [length(lines), cur_col]
        end
        cur_col -= length(line)+1
    end
    current_buffer(nv)[:] = lines
    set_cursor(current_window(nv), cursor)

    rstate.active = true
    while rstate.active
        char = read(term, Uint8)
        if !rstate.active
            # FIXME: handle this in a better way
            break
        end

        input(nv, bytestring([char]))
        #LineEdit.edit_insert
        if char == 1; rstate.active = false; end
        update_screen()
    end
end


repl = Base.active_repl
main_mode = repl.interface.modes[1]
main_mode.keymap_dict = LineEdit.keymap_merge(main_mode.keymap_dict, LineEdit.normalize_keys(nvim_keymap))

nothing

