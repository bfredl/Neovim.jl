" FIXME: resolve path to script
let g:julia_channel = jobstart(["julia", "../test/child.jl"], {'rpc': v:true})
function! JTest()
    call rpcnotify(g:julia_channel, "testing", "2+2")
endfunction
