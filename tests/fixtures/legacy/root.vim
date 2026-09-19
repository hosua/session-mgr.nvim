let SessionLoad = 1
let s:so_save = &g:so | let s:siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1
let v:this_session=expand("<sfile>:p")
silent only
silent tabonly
cd ~/proj/demo
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
badd +219 src/deployer.js
badd +78 src/deployer.spec.js
badd +3 docs/with\ space.md
argglobal
%argdel
edit src/deployer.spec.js
wincmd _ | wincmd |
vsplit
1wincmd h
wincmd w
tabnew +setlocal\ bufhidden=wipe
edit docs/with\ space.md
tabnext 1
