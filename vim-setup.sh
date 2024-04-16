#!/bin/bash
# Install Vundle
git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
# Replace local .vimrc
cp .vimrc ~/.vimrc
# Don't forget to run :PluginInstall in vim
