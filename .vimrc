" Prevent a user from using arrow keys
noremap <Up> <NOP>
noremap <Down> <NOP>
noremap <Left> <NOP>
noremap <Right> <NOP>
imap <Up> <NOP>
imap <Down> <NOP>
imap <Left> <NOP>
imap <Right> <NOP>

" Tabs and text formatting stuff
set expandtab
set tabstop=4
set softtabstop=4
set shiftwidth=4

" Vundle plugin manager.
set nocompatible
filetype off
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
Plugin 'VundleVim/Vundle.vim'                       " Vundle
Plugin 'preservim/nerdtree'                         " NERDTree
Plugin 'Xuyuanp/nerdtree-git-plugin'                " NERDTree git status highlight
Plugin 'ryanoasis/vim-devicons'                     " NERDTree custom folder and files icons
Plugin 'tiagofumo/vim-nerdtree-syntax-highlight'    " NERDTree smth
Plugin 'itchyny/lightline.vim'                      " Custom status line
Plugin 'rafi/awesome-vim-colorschemes'              " More colorschemes for colorschemes god
Plugin 'vim-syntastic/syntastic'                    " Syntax error highlighter
Plugin 'tpope/vim-fugitive'                         " Smth for git
Plugin 'vshih/vim-make'                             " Smth for make
call vundle#end()
filetype plugin indent on

" Colorschemes and other highlighting stuff
set background=dark
colorscheme solarized8

" NERDTree settings
"nnoremap <leader>n :NERDTreeFocus<CR>
"nnoremap <C-n> :NERDTree<CR>
"nnoremap <C-t> :NERDTreeToggle<CR>
"nnoremap <C-f> :NERDTreeFind<CR>
"
"autocmd VimEnter * ++nested NERDTree | wincmd p " ++nested to solve lightline conflict
"autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif
"let g:NERDTreeWinPos = "right"
"let NERDTreeShowHidden=1

" Syntastic settings
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0

" Lightline
set laststatus=2
set number
set noshowmode
if !has('gui_running')
   set t_Co=256
 endif
" let g:lightline = {'colorscheme': 'wombat',}

"colorscheme apprentice
" let g:rainbow_active = 1 " Rainbow brackets
