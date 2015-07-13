# Neovim client for julia

[![Build Status](https://travis-ci.org/bfredl/Neovim.jl.svg?branch=master)](https://travis-ci.org/bfredl/Neovim.jl)

This is a neovim api client for julia. It supports embedding a nvim process in julia and conversely acting as a child process to nvim, as well as connecting to an external instance over a socket. It also works as a plugin host. Currently it assumes `nvim` is in `$PATH`

Simplest way to test the api client is to spawn an embedded instance:
```julia
using Neovim
nvim, proc = nvim_spawn()
```
or connecting to an external instance:
```julia
nvim = nvim_connect("/socket/address")
```
(this address can be found by `:echo $NVIM_LISTEN_ADDRESS` in nvim)

As a shortcut, `nvim = nvim_env()` will use the address in `$NVIM_LISTEN_ADDRESS`. This is useful to connect to the "parent" nvim instance when running the Julia REPL in a nvim terminal window.

All API methods defined in metadata is defined as corresponding julia functions on the `Neovim` module, except that the `vim_`/`buffer_` prefix is dropped (as the reciever type is identified by the first argument anyway), except for `vim_eval` as `eval` is not overloadable. For instance:
```julia
import Neovim: get_buffers, set_line, vim_eval
buf = get_buffers(nvim)[1]
set_line(buf, 1, "some text")
@assert vim_eval(nvim, "2+2") == 4
```

A high level interface is work in progress. For the moment `Buffer` supports simple array operations, please see `test/runtests.jl` for examples.

The module exports a low-level interface for handling asynchronous events (notifications and requests). A prototype (read: ugly hack) implementation of vim bindings for the julia REPL is included as an example, see `src/repl.jl`.

This package also includes a remote plugin host, similar to the one in python-client. To use it, it is recommended to manage this package using the Julia package manager (as it handles dependencies and julia package path), and also add this repo root to runtimepath in nvimrc:

    set rtp+=~/.julia/Neovim/

A julia plugin can then be defined in a `rplugin/julia/` subfolder to your nvim folder or to a plugin repo. Functions defined at toplevel can be exported using macros in the Neovim module. `@fn`, `@command`, `@autocmd` can be used, as well as variants ending with `sync`.
```julia
module MyPlugin
using Neovim

@Neovim.fn function AsyncFun(nvim, args)
    # "args" is Vector of arguments passed to ":call AsyncFun(args...)".
end

@Neovim.fnsync function SyncFun(nvim, args)
    # This will block neovim while SyncFun is running.
end

@Neovim.fnsync OneLiner(nvim, args) = "expression"

# Add some options. -> is required to define function on next line.
@Neovim.commandsync (nargs="*", range="") ->
function JLCommand(nvim, args, range)
end

# The name of the function/command can also be defined on the macro.
# This is equivalent to the above.
@Neovim.commandsync JLCommand(nargs="*", range="") ->
function (nvim, args, range)
end

end
```
