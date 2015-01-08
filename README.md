# Neovim client for julia

[![Build Status](https://travis-ci.org/bfredl/Neovim.jl.svg?branch=master)](https://travis-ci.org/bfredl/Neovim.jl)

This is a simple neovim api client for julia. It supports embedding a nvim process in julia and conversely acting as a child process to nvim, as well as connecting to an external instance over a socket. Currently it assumes `nvim` is in `$PATH`

Simplest way to test this is to spawn an embedded instance:
```
using Neovim
nvim, proc = nvim_spawn()
```
or connecting to an external instance:
```
nvim = nvim_connect("/socket/address")
```
(this address can be found by `:echo $NVIM_LISTEN_ADRESS` in nvim)

All API methods defined in metadata is defined as corresponding julia functions on the `Neovim` module, except that the `vim_`/`buffer_` prefix is dropped (as the reciever type is identified by the first argument anyway), except for `vim_eval` as `eval` is not overloadable. For instance:
```
import Neovim: get_buffers, set_line, vim_eval
buf = get_buffers(nvim)[1]
set_line(buf, 1, "some text")
@assert vim_eval(nvim, "2+2") == 4
```

A high level interface is work in progress. For the moment `Buffer` supports simple array operations, please see `test/runtests.jl` for examples.

At the moment the module export a low-level interface for handling asynchronous events (notifications and requests). A high-level interface for defining plugins with callback handlers, similar to the python-client, might be added later.

A prototype (read: ugly hack) implementation of vim bindings for the julia REPL is included as an example, see `src/repl.jl`.

