#TEST
module MyPlugin
using Neovim
import Neovim: get_var, set_var, vim_eval

# allow zero, one or many options
# allow handler on same line or continued with ->
# allow name on options or on handler
# allow one-line or muli-line method def

# println(macroexpand(Neovim, :(@Neovim.fn(function AsyncFun(nvim, args) print(args) end))))

@Neovim.fn (sync=true) TestFun(nvim, args) = "TestFun got " * join(args, ", ")

@Neovim.fn function AsyncFun(nvim, args)
    set_var(nvim, "args", args)
    vim_eval(nvim, "rpcnotify(g:args[0], 'AsyncReply', g:args[1])")
end

@Neovim.command JLCommand(nargs="*", range="", sync=true) ->
function (nvim, args, range)
    push!(current_buffer(nvim), args[1])
    set_var(nvim, "therange", range)
end

@Neovim.commandsync function Explode(nvim)
    error("KABOOM!")
end

@Neovim.autocmd User(pattern="zing", sync=true) (nvim) -> set_var(nvim, "zinged", get_var(nvim, "zinged")+1)

globvar = 3
@Neovim.fnsync Global(nvim, args) = globvar

let locvar = 37
    @Neovim.fn (sync=true) Local(nvim, args) = locvar
end

end
