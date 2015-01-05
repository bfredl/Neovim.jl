" FIXME: resolve path to script
let g:julia_channel = rpcstart("julia", ["../test/child.jl"])
function! JTest()
    call rpcnotify(g:julia_channel, "testing", "2+2")
endfunction
