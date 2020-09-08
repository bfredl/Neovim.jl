function! julia_neo#RequireJuliaHost(host)
  " Julia host arguments
  let prog = get(g:, 'julia_host_prog', 'julia')

  try
    return jobstart([prog, '-e', 'using Neovim; start_host()'], {'rpc': v:true})
  catch
    echomsg v:exception
  endtry
  throw 'Failed to load Julia host. You can try to see what happened '.
        \ 'by starting Neovim with the environment variable '.
        \ '$NVIM_JL_DEBUG set to a file and opening '.
        \ 'the generated log file. Also, the host stderr will be available '.
        \ 'in Neovim log, so it may contain useful information. '.
        \ 'See also ~/.nvimlog.'
endfunction
