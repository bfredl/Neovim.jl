# Neovim client for Julia

[![Build Status](https://travis-ci.org/bfredl/Neovim.jl.svg?branch=master)](https://travis-ci.org/bfredl/Neovim.jl)

Neovim.jl is a Neovim API client and plugin host for Julia. It supports:

- Embedding a nvim process in Julia
- Acting as a child process to nvim
- Connecting to external instances over a socket


## Requirements

- Julia ≥ 1.0
- Neovim ≥ 0.4 (this package assumes `nvim` is in `$PATH`)


## Installation

Add this package to your current Julia environment:
```julia
using Pkg
Pkg.add(url="https://github.com/bfredl/Neovim.jl")
```


## Usage

### As an embedded process

The simplest way to test the API client is to spawn an embedded instance:
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


All API methods defined in the Neovim metadata (see `:h api-metadata`) are defined as corresponding Julia functions on the `Neovim` module (these functions are not exported, use `import` syntax), except that the `vim_`/`buffer_` prefix is dropped (as the receiver type is identified by the first argument anyway), except for `vim_eval` as `eval` is not overloadable. For instance:
```julia
import Neovim: get_buffers, set_line, vim_eval
buf = get_buffers(nvim)[1]
set_line(buf, 1, "some text")
@assert vim_eval(nvim, "2+2") == 4
```

A high level interface is work in progress. For the moment `Buffer` supports simple array operations, please see `test/runtests.jl` for examples.

The module exports a low-level interface for handling asynchronous events (notifications and requests). A prototype (read: ugly hack) implementation of Vim bindings for the Julia REPL is included as an example, see `src/repl.jl`.


### As a plugin host

This package also includes a remote plugin host, similar to the one in the Python client [pynvim](https://github.com/neovim/pynvim). To use it, add this repo root to `runtimepath` in `init.vim`:
```
set rtp+=~/.julia/packages/Neovim/
```
A Julia plugin can then be defined in a `rplugin/julia/` subdirectory inside a directory in your `runtimepath` (See `:h remote-plugin` and `:h runtimepath`) or inside a plugin directory (see `:h packages` or your package manager's docs).

Functions defined at the top-level of your script can be exported using the macros: `@fn`, `@command`, `@autocmd`, as well as variants ending with `sync`.

For example:

```julia
# In MyPlugin/rplugin/julia/MyPlugin.jl

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

After writing your Julia script, you should call `:UpdateRemotePlugins` to
register these functions and make them callable from Vimscript and Lua.
