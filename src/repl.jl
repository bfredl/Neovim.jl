# mostly a proof-of-concept (more explicitly: a terrible hack) for the moment
import Base: LineEdit, REPL
using Neovim
import Neovim: feedkeys, get_current_line, get_current_window, get_current_buffer
import Neovim: get_cursor, set_cursor, set_line, command

type NvimReplState
    active::Bool
    nv::NvimClient
    nbuf::Buffer
    win::Window
    s::LineEdit.MIState
    rbuf::IOBuffer
    function NvimReplState()
        state = new(false)
        state.nv, proc = nvim_spawn(state)
        state.nbuf = get_current_buffer(state.nv)
        state.win = get_current_window(state.nv)
        state
    end
end
function Neovim.on_notify(s::NvimReplState, nv, name, args)
    @async begin
        update_screen()
        if name == "update"
            #done
        elseif name == "insert" 
            feedkeys(nv, "\033", "", false)
            s.active = false
        end
    end
end

const rstate = NvimReplState()
const channel = rstate.nv.channel_id

command(rstate.nv, "au CursorMoved,TextChanged * call rpcnotify($channel, 'update')")
command(rstate.nv, "au InsertEnter * call rpcnotify($channel, 'insert')")


const nvim_keymap = {
    "^O" => function (s,repl,c)
        ps = LineEdit.state(s, LineEdit.mode(s))
        nvim_normal(ps.terminal,s,repl)
    end
}

function update_screen()
    if !rstate.active
        return
    end
    nv = rstate.nv
    #FIXME: this is a terrible hack, use abstract_ui later
    line = get_current_line(nv)
    pos = get_cursor(rstate.win)[2]
    truncate(rstate.rbuf, 0)
    write(rstate.rbuf, line)
    seek(rstate.rbuf, pos)
    LineEdit.refresh_line(rstate.s)
end

function nvim_normal(term, s, repl)
    rstate.s = s
    rstate.rbuf = rbuf = LineEdit.buffer(s)
    nv = rstate.nv

    buf_pos = position(rbuf)
    seek(rbuf, 0)
    set_line(rstate.nbuf, 1, readline(rbuf))
    set_cursor(rstate.win, Any[1, buf_pos])
    rstate.active = true
    while rstate.active
        char = read(term, Uint8)
        if !rstate.active
            # FIXME: handle this in a better way
            break
        end

        feedkeys(nv, bytestring([char]), "", true)
        #LineEdit.edit_insert
        if char == 1; rstate.active = false; end
        update_screen()
    end
end


repl = Base.active_repl
main_mode = repl.interface.modes[1]
main_mode.keymap_dict = LineEdit.keymap_merge(main_mode.keymap_dict, LineEdit.normalize_keys(nvim_keymap))

nothing

