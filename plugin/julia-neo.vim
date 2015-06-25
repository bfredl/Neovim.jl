function! s:RequireJuliaHost(name)
  " Julia host arguments
  let args = ['-e', 'using Neovim; start_host()']

  try
    return rpcstart('julia', args)
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

call remote#host#Register('julia', '*.jl', function('s:RequireJuliaHost'))
