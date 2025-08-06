#!/usr/bin/env bash
set -euo pipefail

# ======================== Config & Helpers ========================

# List of all components
ALL_COMPONENTS=(cli gui ssh ohmyzsh neovim telegram python-venv pyenv go nvim-config fonts docker)

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; }

# Require sudo (or root)
require_sudo() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      err "This script needs root privileges (install sudo or run as root)."
      exit 1
    fi
  else
    SUDO=""
  fi
}

# Run apt-get update once
APT_UPDATED=0
apt_update_once() {
  if [[ $APT_UPDATED -eq 0 ]]; then
    log "Updating apt package index..."
    $SUDO apt-get update -y
    APT_UPDATED=1
  fi
}

# Idempotent append to a file
append_once() {
  local line="$1" file="$2"
  grep -Fqx "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# Detect architecture and codename
ARCH="$(dpkg --print-architecture)"
UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"

# Ensure some dirs
mkdir -p "$HOME/personal" "$HOME/.config" "$HOME/.local/share/fonts" "$HOME/.ssh"

# ======================== Components ==============================

component_cli() {
  require_sudo
  apt_update_once
  log "Installing CLI packages..."
  $SUDO apt-get install -y \
    curl zsh git make cmake gettext lightdm \
    i3 tmux jq fzf nodejs npm build-essential libssl-dev \
    zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    wget llvm libc6 libssl3 libx11-xcb1 xclip net-tools  \
    samba maim ripgrep
  # Default shell to zsh (non-interactive)
  if command -v zsh >/dev/null 2>&1; then
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
      log "Setting default shell to zsh..."
      chsh -s "$(command -v zsh)" || warn "Could not change default shell automatically."
    fi
  fi
}

component_gui() {
  require_sudo
  apt_update_once
  log "Installing GUI packages (LightDM + i3)..."
  $SUDO apt-get install -y lightdm i3
}

component_ssh() {
  require_sudo
  apt_update_once
  log "Ensuring OpenSSH client..."
  $SUDO apt-get install -y openssh-client
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    log "Generating SSH key (ed25519, no passphrase)..."
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
  else
    log "SSH key already exists, skipping."
  fi
}

component_ohmyzsh() {
  # Non-interactive oh-my-zsh install
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Installing oh-my-zsh (non-interactive)..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    log "oh-my-zsh already installed, skipping."
  fi

  # Plugins
  local CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$CUSTOM/plugins"
  if [[ ! -d "$CUSTOM/plugins/zsh-autosuggestions" ]]; then
    log "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$CUSTOM/plugins/zsh-autosuggestions"
  else
    log "zsh-autosuggestions already present, skipping."
  fi
  if [[ ! -d "$CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    log "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$CUSTOM/plugins/zsh-syntax-highlighting"
  else
    log "zsh-syntax-highlighting already present, skipping."
  fi
}

component_neovim() {
  require_sudo
  # Build Neovim v0.10.3 from source
  if ! command -v nvim >/dev/null 2>&1; then
    log "Cloning and building Neovim v0.10.3..."
    if [[ ! -d "$HOME/personal/neovim" ]]; then
      git clone -b v0.10.3 https://github.com/neovim/neovim.git "$HOME/personal/neovim"
    else
      log "Neovim source already exists, pulling latest for v0.10.3..."
      (cd "$HOME/personal/neovim" && git fetch --all && git checkout v0.10.3)
    fi
    (cd "$HOME/personal/neovim" && make && $SUDO make install)
  else
    log "Neovim already installed, skipping build."
  fi
}

component_telegram() {
  require_sudo
  apt_update_once
  if ! command -v snap >/dev/null 2>&1; then
    log "Installing snapd..."
    $SUDO apt-get install -y snapd
  fi
  if ! snap list | grep -q '^telegram-desktop '; then
    log "Installing Telegram Desktop via snap..."
    $SUDO snap install telegram-desktop
  else
    log "Telegram Desktop already installed, skipping."
  fi
}

component_python_venv() {
  require_sudo
  apt_update_once
  log "Installing Python venv package..."
  # Prefer generic package; fallback to 3.8 if available on your base image
  if $SUDO apt-get install -y python3-venv; then
    :
  else
    warn "python3-venv not available, trying python3.8-venv..."
    $SUDO apt-get install -y python3.8-venv || warn "Could not install python venv package."
  fi
}

component_pyenv() {
  # Install pyenv
  if [[ ! -d "$HOME/.pyenv" ]]; then
    log "Installing pyenv..."
    curl -fsSL https://pyenv.run | bash
  else
    log "pyenv already installed, skipping."
  fi

  # Init pyenv for this script run
  export PYENV_ROOT="$HOME/.pyenv"
  [[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
  # Newer pyenv recommends: eval "$(pyenv init -)"
  eval "$(pyenv init -)"

  # Ensure zshrc contains pyenv init lines
  append_once 'export PYENV_ROOT="$HOME/.pyenv"' "$HOME/.zshrc"
  append_once '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' "$HOME/.zshrc"
  append_once 'eval "$(pyenv init -)"' "$HOME/.zshrc"

  # Install and set Python 3.10.18
  if ! pyenv versions --bare | grep -qx "3.10.18"; then
    log "Installing Python 3.10.18 via pyenv (this can take a while)..."
    pyenv install 3.10.18
  else
    log "Python 3.10.18 already installed in pyenv."
  fi
  log "Setting global Python version to 3.10.18..."
  pyenv global 3.10.18
}

component_go() {
  require_sudo
  # Remove existing Go if present
  if [[ -d /usr/local/go ]]; then
    log "Removing existing Go installation at /usr/local/go..."
    $SUDO rm -rf /usr/local/go
  fi
  log "Installing latest Go for architecture: $ARCH ..."
  curl -sSL "https://go.dev/dl/$(curl -s https://go.dev/dl/\?mode=json | jq -r '.[0].version').linux-${ARCH}.tar.gz" \
    --output /tmp/go.tar.gz
  $SUDO tar -C /usr/local -xzf /tmp/go.tar.gz
  log "Installing delve debugger..."
  /usr/local/go/bin/go install github.com/go-delve/delve/cmd/dlv@latest || warn "Failed to install delve."
}

component_nvim_config() {
  # Clone your Neovim config into ~/.config/nvim
  if [[ ! -d "$HOME/.config/nvim" ]]; then
    log "Cloning Neovim config into ~/.config/nvim ..."
    git clone https://github.com/sergeybrian/nvim "$HOME/.config/nvim"
  else
    log "Neovim config already exists, pulling updates..."
    (cd "$HOME/.config/nvim" && git pull --ff-only) || warn "Could not update existing nvim config."
  fi
}

component_fonts() {
  # Install JetBrainsMono Nerd Font
  local zip="/tmp/JetBrainsMono.zip"
  if [[ ! -f "$HOME/.local/share/fonts/JetBrains Mono Regular Nerd Font Complete Mono.ttf" ]] && \
     [[ ! -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf" ]]; then
    log "Installing JetBrainsMono Nerd Font..."
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip" -o "$zip"
    unzip -o "$zip" -d "$HOME/.local/share/fonts" >/dev/null
    fc-cache -f || true
  else
    log "JetBrainsMono Nerd Font seems present, skipping."
  fi
}

component_docker() {
  require_sudo
  apt_update_once
  log "Removing any conflicting docker/podman packages..."
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    $SUDO apt-get -y remove "$pkg" >/dev/null 2>&1 || true
  done

  log "Installing Docker CE from official repo..."
  $SUDO apt-get install -y ca-certificates curl
  $SUDO install -m 0755 -d /etc/apt/keyrings
  $SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  $SUDO chmod a+r /etc/apt/keyrings/docker.asc

  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

  $SUDO apt-get update -y
  $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Add current user to docker group (effective after re-login)
  if getent group docker >/dev/null 2>&1; then
    $SUDO usermod -aG docker "$USER" || true
    log "Added user '$USER' to docker group (log out/in to take effect)."
  fi
}

# ======================== Argument Parsing ========================

usage() {
  cat <<EOF
Usage: $0 [component ...] | all | --list | --help

Components:
  ${ALL_COMPONENTS[*]}

Examples:
  $0 all
  $0 cli docker
  $0 cli ohmyzsh neovim nvim-config
EOF
}

list_components() {
  printf "%s\n" "${ALL_COMPONENTS[@]}"
}

if [[ $# -eq 0 ]]; then
  warn "No components specified. Defaulting to 'all'."
  set -- all
fi

SELECTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --list) list_components; exit 0 ;;
    all) SELECTED=("${ALL_COMPONENTS[@]}"); shift ;;
    *)
      # validate component
      found=0
      for c in "${ALL_COMPONENTS[@]}"; do
        if [[ "$1" == "$c" ]]; then found=1; break; fi
      done
      if [[ $found -eq 0 ]]; then
        err "Unknown component: $1"
        usage
        exit 1
      fi
      SELECTED+=("$1")
      shift
      ;;
  esac
done

# Remove duplicates from SELECTED
mapfile -t SELECTED < <(printf "%s\n" "${SELECTED[@]}" | awk '!seen[$0]++')

# ======================== Execution ===============================

log "Selected components: ${SELECTED[*]}"

for comp in "${SELECTED[@]}"; do
  case "$comp" in
    cli)          component_cli ;;
    gui)          component_gui ;;
    ssh)          component_ssh ;;
    ohmyzsh)      component_ohmyzsh ;;
    neovim)       component_neovim ;;
    telegram)     component_telegram ;;
    python-venv)  component_python_venv ;;
    pyenv)        component_pyenv ;;
    go)           component_go ;;
    nvim-config)  component_nvim_config ;;
    fonts)        component_fonts ;;
    docker)       component_docker ;;
    *) err "Internal error: handler not found for '$comp'"; exit 2 ;;
  esac
done

log "All requested components finished."
