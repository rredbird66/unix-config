#!/bin/bash
# For root install
# sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
# For user install
mkdir ~/.oh_my_posh
wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O ~/.oh_my_posh/oh-my-posh
chmod +x ~/.oh_my_posh/oh-my-posh
# Themes
mkdir ~/.poshthemes
#wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip -O ~/.poshthemes/themes.zip
#unzip ~/.poshthemes/themes.zip -d ~/.poshthemes
#chmod u+rw ~/.poshthemes/*.json
#rm ~/.poshthemes/themes.zip
cp paradox.omp.json ~/.poshthemes
chmod u+rw ~/.poshthemes/*.json
# Deploy .bashrc
cat .bashrc >> ~/.bashrc
# For proper o-m-p display you need to install any Nerd Font
