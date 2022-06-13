#!/bin/bash
echo 'Creating symlinks'
ln -s ~/.dotfiles/tmux/tmux.conf ~/.tmux.conf
ln -s ~/.dotfiles/vim/vimrc ~/.vimrc
ln -s ~/.dotfiles/zsh/zshrc ~/.zshrc


echo 'Downloading tmux plugin manager'
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm


echo 'Downloading Oh My Zsh'
-c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
