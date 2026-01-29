:set relativenumber
:set number
:set number relativenumber
:set nowrap
:set tabstop=4
:set softtabstop=4
:set shiftwidth=4
:set expandtab
:set autoindent
:set smarttab
:set smartcase
:set smartindent
:set showmode
":set clipboard=wl-copy
:set clipboard=unnamedplus
":set surround
:set breakindent
:set undofile
:set ignorecase
:set smartcase
:set splitright
:set splitbelow
:set cursorlineopt=both
:set guicursor=i:ver25-blinkon0
:set conceallevel=1
:set numberwidth=3
":set signcolumn=yes:1
:set mouse=a
:set scrolloff=5
:set incsearch
:set ruler
":set whichkey
":set textobj-indent
":set textobj-entire
":set argtextobj
":set commentary
:set vb
":set autochdir
:set foldcolumn=1
:set foldlevel=99
:set foldlevelstart=99
":set foldenable=true
:set textwidth=0
":set textwidth=120
:set formatoptions-=t
:set colorcolumn=120
:set formatoptions-=l
:set sessionoptions+=localoptions
"inoremap <CR> pumvisible() ? "<C-Y>" : "<CR>"
let g:python3_host_prog = '/usr/bin/python3'
"let &t_SI = "\<esc>[5 q"  " blinking I-beam in insert mode
"let &t_SR = "\<esc>[3 q"  " blinking underline in replace mode
"let &t_EI = "\<esc>[ q"  " default cursor (usually blinking block) otherwise
"let $NVIM_TUI_ENABLE_CURSOR_SHAPE=1
set termguicolors
"hi Cursor guifg=green guibg=green
"hi CursorIM guifg=red guibg=red
"set guicursor=n-v-c:block-Cursor/lCursor,i-ci-ve:ver25-CursorIM/lCursorIM,r-cr:hor20,o:hor50
":set guicursor=n-v-c-i:block,i:ver100
"if exists('$TMUX')
"    let &t_SI .= "\Ptmux;\[6 q\"
"    let &t_SI .= "\Ptmux;\]12;orange\x7\"
"endif
"if exists('$TMUX')
"    let &t_SI = "\Ptmux;\e[5 q\e\\"
"    let &t_EI = "\Ptmux;\e[2 q\e\\"
"else
"    let &t_SI = "\e[5 q"
"    let &t_EI = "\e[2 q"
"endif
"if &term =~ "xterm\|rxvt"
"    let &t_SI .= "\e[5 q" " insert mode - vertical bar
"    let &t_EI .= "\e[2 q" " normal mode - block
"endif

if has('ide')

endif
