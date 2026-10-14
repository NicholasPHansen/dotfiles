# Dotfiles

zsh (oh-my-zsh + powerlevel10k), tmux and Neovim (LazyVim) for macOS and Linux.

## Install

```sh
git clone git@github.com:NicholasPHansen/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && ./setup.sh
```

The repo can live anywhere; links point at wherever you cloned it.
`setup.sh` is safe to re-run. It asks for your sudo password once at the
start and keeps it cached, so the rest runs unattended. It:

1. installs packages with Homebrew (macOS), dnf or apt (Linux) — Neovim on
   Linux comes from the official release into `~/.local`, since distro
   packages are usually too old for LazyVim;
2. installs oh-my-zsh and its plugins;
3. links the configs, moving anything already there to `~/.dotfiles-backup/<timestamp>/`;
4. makes zsh your login shell;
5. installs tmux plugins and restores Neovim plugins from `nvim/lazy-lock.json`;
6. prints what is left to do.

Use `./setup.sh --no-pkgs` to skip package installation. Without sudo the
script still links configs, installs plugins and puts Neovim in `~/.local`.

| Repo            | Linked to          |
| --------------- | ------------------ |
| `zsh/zshrc`     | `~/.zshrc`         |
| `tmux/tmux.conf`| `~/.tmux.conf`     |
| `nvim/`         | `~/.config/nvim`   |

## Neovim

LazyVim with the Python, Julia, Markdown, Docker, JSON/YAML/TOML and DAP
extras (see `nvim/lazyvim.json`). Personal plugins live in `nvim/lua/plugins/`.

- `image.nvim` renders images inline. It needs ImageMagick and a terminal that
  speaks the kitty graphics protocol (kitty, ghostty, wezterm).
- Plugin versions are pinned in `nvim/lazy-lock.json`. After `:Lazy update`,
  commit the lockfile so every machine gets the same versions.

## tmux

Plugins via tpm (`prefix + I` installs them if `setup.sh` could not). The
config enables passthrough (inline images in Neovim), OSC 52 clipboard and
true colour, so the same setup works over SSH.
