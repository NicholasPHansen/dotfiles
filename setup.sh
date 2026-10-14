#!/usr/bin/env bash
# Dotfiles bootstrap for macOS (Homebrew) and Linux (dnf / apt).
#
#   ./setup.sh            install packages, link configs, install plugins
#   ./setup.sh --no-pkgs  only link configs and install plugins
#
# Safe to re-run: existing files are backed up once, links are refreshed,
# and anything already installed is skipped.

set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
INSTALL_PKGS=1
[[ "${1:-}" == "--no-pkgs" ]] && INSTALL_PKGS=0

OS="$(uname -s)"
ARCH="$(uname -m)"
USER="${USER:-$(id -un)}"
FAILED=()
NOTES=()

# ---------------------------------------------------------------- output ----
if [[ -t 1 ]]; then
  B=$'\e[1m' DIM=$'\e[2m' R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m' N=$'\e[0m'
else
  B="" DIM="" R="" G="" Y="" C="" N=""
fi
step() { printf '\n%s==>%s %s%s%s\n' "$C" "$N" "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
skip() { printf '  %s· %s%s\n' "$DIM" "$*" "$N"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
fail() { printf '  %s✗%s %s\n' "$R" "$N" "$*"; FAILED+=("$*"); }
have() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------- packages ---
# Each entry is "command:package" — the command is checked before installing.
# Alternatives for a package name are separated by '|' and tried in order.
COMMON_PKGS=(
  git:git zsh:zsh tmux:tmux curl:curl unzip:unzip make:make
  rg:ripgrep fzf:fzf "node:node|nodejs" npm:npm python3:python3
  magick:imagemagick "pdftotext:poppler|poppler-utils" lsd:lsd
  "mc:midnight-commander|mc"
)
MAC_PKGS=(nvim:neovim fd:fd lazygit:lazygit "tree-sitter:tree-sitter-cli|tree-sitter")
DNF_PKGS=(fd:fd-find gcc:gcc lazygit:lazygit)
APT_PKGS=(fdfind:fd-find gcc:build-essential lazygit:lazygit)

detect_pm() {
  if [[ "$OS" == "Darwin" ]]; then echo brew
  elif have dnf; then echo dnf
  elif have apt-get; then echo apt
  else echo none
  fi
}
PM="$(detect_pm)"

pm_install() {  # pm_install <package>
  case "$PM" in
    brew) brew install "$1" ;;
    dnf)  $SUDO dnf install -y "$1" ;;
    apt)  $SUDO apt-get install -y "$1" ;;
  esac
}

install_pkg() {  # install_pkg "cmd:pkg1|pkg2"
  local cmd="${1%%:*}" alts="${1#*:}" pkg
  if have "$cmd"; then skip "$cmd already installed"; return; fi
  IFS='|' read -ra opts <<<"$alts"
  for pkg in "${opts[@]}"; do
    if pm_install "$pkg" >/dev/null 2>&1; then ok "installed $pkg"; return; fi
  done
  fail "could not install ${alts//|/ or } (provides $cmd)"
}

ensure_homebrew() {
  have brew && return
  step "Installing Homebrew"
  if ((!HAVE_SUDO)); then fail "Homebrew install needs sudo — skipped"; return 1; fi
  # NONINTERACTIVE skips the "press RETURN" prompt; sudo is already cached
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available for the rest of this run
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [[ -x /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
}

# LazyVim needs a recent Neovim; distro packages are often too old, so on
# Linux install the official release into ~/.local.
install_neovim_linux() {
  local want="0.11"
  if have nvim; then
    local v; v="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    if [[ "$(printf '%s\n%s\n' "$want" "$v" | sort -V | head -1)" == "$want" ]]; then
      skip "nvim $v already installed"; return
    fi
    warn "nvim $v is older than $want, installing the official release"
  fi
  local a; case "$ARCH" in x86_64) a=x86_64 ;; aarch64|arm64) a=arm64 ;; *) fail "no Neovim release for $ARCH"; return ;; esac
  local url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${a}.tar.gz"
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
  if curl -fsSL "$url" | tar -xz -C "$HOME/.local/opt"; then
    ln -sfn "$HOME/.local/opt/nvim-linux-${a}/bin/nvim" "$HOME/.local/bin/nvim"
    export PATH="$HOME/.local/bin:$PATH"
    ok "installed Neovim to ~/.local/opt (linked in ~/.local/bin)"
  else
    fail "Neovim download failed ($url)"
  fi
}

install_packages() {
  step "Installing packages ($PM)"
  if [[ "$PM" != brew ]] && ((!HAVE_SUDO)); then
    warn "no sudo — skipping system packages, installing Neovim to ~/.local only"
    [[ "$PM" != none ]] && install_neovim_linux
    return
  fi
  case "$PM" in
    brew) ensure_homebrew || return; for p in "${COMMON_PKGS[@]}" "${MAC_PKGS[@]}"; do install_pkg "$p"; done ;;
    dnf)  for p in "${COMMON_PKGS[@]}" "${DNF_PKGS[@]}"; do install_pkg "$p"; done; install_neovim_linux ;;
    apt)  $SUDO apt-get update -qq
          for p in "${COMMON_PKGS[@]}" "${APT_PKGS[@]}"; do install_pkg "$p"; done; install_neovim_linux
          # Debian/Ubuntu ship fd as fdfind
          if have fdfind && ! have fd; then mkdir -p "$HOME/.local/bin"; ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"; ok "linked fdfind -> fd"; fi ;;
    none) fail "no supported package manager (brew, dnf, apt) — install packages manually"; return ;;
  esac
  # tree-sitter CLI (nvim-treesitter compiles parsers with it); npm works everywhere
  if ! have tree-sitter && have npm; then
    if npm install -g tree-sitter-cli >/dev/null 2>&1; then ok "installed tree-sitter-cli (npm)"
    else fail "could not install tree-sitter-cli (try: npm install -g tree-sitter-cli)"; fi
  fi
}

# ------------------------------------------------------------------ links ---
link() {  # link <source in repo> <target>
  local src="$DOTFILES/$1" dst="$2"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then skip "$dst already linked"; return; fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/" && warn "backed up existing $dst to $BACKUP_DIR/"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst" && ok "$dst -> $src"
}

link_configs() {
  step "Linking configs"
  link tmux/tmux.conf "$HOME/.tmux.conf"
  link zsh/zshrc      "$HOME/.zshrc"
  link nvim           "$HOME/.config/nvim"
}

# -------------------------------------------------------------- shell/zsh ---
install_zsh_stack() {
  step "Oh My Zsh and plugins"
  if [[ -d "$HOME/.oh-my-zsh" ]]; then skip "oh-my-zsh already installed"
  else
    # KEEP_ZSHRC stops the installer replacing our linked ~/.zshrc
    local installer
    if ! installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
      fail "could not download the oh-my-zsh installer"
    elif RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$installer" "" --unattended >/dev/null; then
      ok "installed oh-my-zsh"
    else fail "oh-my-zsh install failed"; fi
  fi
  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  clone https://github.com/romkatv/powerlevel10k.git            "$custom/themes/powerlevel10k"
  clone https://github.com/zsh-users/zsh-autosuggestions.git    "$custom/plugins/zsh-autosuggestions"
  clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting"
}

clone() {  # clone <url> <dir>
  if [[ -d "$2/.git" ]]; then skip "$(basename "$2") already present"; return; fi
  if git clone --depth=1 -q "$1" "$2"; then ok "cloned $(basename "$2")"; else fail "could not clone $1"; fi
}

# ---------------------------------------------------------------- plugins ---
install_plugins() {
  step "tmux plugins"
  clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  if [[ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    if "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1; then ok "tmux plugins installed"
    else warn "tmux plugin install did not finish — press prefix + I inside tmux"; NOTES+=("tmux: press ${B}prefix + I${N} to install plugins"); fi
  fi

  step "Neovim plugins (lazy.nvim, pinned by lazy-lock.json)"
  if have nvim; then
    if nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1; then ok "Neovim plugins restored"
    else warn "headless plugin install failed — open nvim and run :Lazy restore"; NOTES+=("Neovim: run ${B}:Lazy restore${N} then ${B}:checkhealth${N}"); fi
  else
    fail "nvim not found — skipped plugin install"
  fi
}

# -------------------------------------------------------------- next steps --
next_steps() {
  local zsh_path; zsh_path="$(command -v zsh || true)"
  step "Done"
  if ((${#FAILED[@]})); then
    printf '\n%sSome steps failed:%s\n' "$R$B" "$N"
    for f in "${FAILED[@]}"; do printf '  %s✗%s %s\n' "$R" "$N" "$f"; done
  fi
  [[ -d "$BACKUP_DIR" ]] && printf '\n%sReplaced files were backed up to:%s %s\n' "$Y" "$N" "$BACKUP_DIR"

  printf '\n%sNext steps%s\n' "$B" "$N"
  local n=1
  for note in "${NOTES[@]}"; do printf '  %d. %s\n' $((n++)) "$note"; done
  [[ -n "$zsh_path" ]] && printf '  %d. Switch this terminal to zsh:    %sexec zsh%s  (new terminals start in zsh)\n' $((n++)) "$C" "$N"
  [[ -f "$HOME/.p10k.zsh" ]] || printf '  %d. Configure the prompt:           %sp10k configure%s\n' $((n++)) "$C" "$N"
  printf '  %d. Check Neovim:                   %snvim%s, then %s:checkhealth%s and %s:Mason%s for LSPs\n' $((n++)) "$C" "$N" "$C" "$N" "$C" "$N"
  printf '  %d. Reload tmux if it is running:   %stmux source-file ~/.tmux.conf%s\n' $((n++)) "$C" "$N"

  printf '\n%sGood to know%s\n' "$B" "$N"
  printf '  %s• Inline images (image.nvim) need a kitty-protocol terminal (kitty, ghostty, wezterm).\n' "$DIM"
  printf '    Over SSH they are drawn by your local terminal; tmux passthrough is enabled in tmux.conf.\n'
  printf '  • Yanks reach your local clipboard over SSH via OSC 52 (set-clipboard on in tmux).\n'
  printf '  • Plugin versions are pinned in nvim/lazy-lock.json — commit it after :Lazy update.%s\n\n' "$N"
}

# -------------------------------------------------------------------- sudo --
# Ask for the password once, up front, and keep the credential cached for the
# rest of the run so nothing stops halfway to prompt.
HAVE_SUDO=0
SUDO=sudo
acquire_sudo() {
  if [[ $EUID -eq 0 ]]; then HAVE_SUDO=1; SUDO=""; return; fi
  if ! have sudo; then warn "sudo not available — system packages and login shell will be skipped"; return; fi
  printf '\n%sAdministrator access%s is needed to install packages and set your login shell.\n' "$B" "$N"
  printf 'Enter your password once; the rest of the setup runs without prompting.\n'
  if sudo -v; then
    HAVE_SUDO=1
    # Refresh the sudo timestamp until this script exits
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
    ok "sudo credentials cached"
  else
    warn "no sudo — continuing with user-level steps only"
  fi
}

# ------------------------------------------------------------ login shell ---
login_shell() {
  if [[ "$OS" == "Darwin" ]]; then dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}'
  else getent passwd "$USER" 2>/dev/null | cut -d: -f7
  fi
}

set_default_shell() {
  step "Login shell"
  local zsh_path current
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then fail "zsh not installed — login shell unchanged"; return; fi
  current="$(login_shell)"; current="${current:-${SHELL:-}}"
  if [[ "$current" == "$zsh_path" ]]; then skip "zsh is already your login shell"; return; fi
  if ((!HAVE_SUDO)); then
    NOTES+=("Make zsh your login shell: ${C}chsh -s $zsh_path${N}")
    warn "no sudo — see next steps to change the login shell"; return
  fi
  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    echo "$zsh_path" | $SUDO tee -a /etc/shells >/dev/null && ok "registered $zsh_path in /etc/shells"
  fi
  if $SUDO chsh -s "$zsh_path" "$USER" >/dev/null 2>&1; then ok "login shell changed to $zsh_path"
  else fail "could not change login shell (try: chsh -s $zsh_path)"; fi
}

# ------------------------------------------------------------------- main ---
printf '%sDotfiles setup%s  %s(%s, %s, repo: %s)%s\n' "$B" "$N" "$DIM" "$OS" "$ARCH" "$DOTFILES" "$N"
acquire_sudo
if ((INSTALL_PKGS)); then install_packages; else step "Skipping packages (--no-pkgs)"; fi
install_zsh_stack
link_configs
set_default_shell
install_plugins
next_steps
