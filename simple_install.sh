#!/bin/bash

sudo apt update
sudo apt install curl zsh git make cmake gettext lightdm \
    i3 tmux jq fzf nodejs npm build-essential libssl-dev \
    zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    wget llvm libc6 libssl3 libx11-xcb1 xclip net-tools  \
    samba maim \
    -y

chsh -s $(which zsh)

ssh-keygen

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting

mkdir $HOME/personal

git clone -b v0.10.3 https://github.com/neovim/neovim.git $HOME/personal/neovim
cd $HOME/personal/neovim
make
sudo make install

sudo snap install telegram-desktop

sudo apt install python3.8-env -y

curl -fsSL https://pyenv.run | bash
echo 'export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
' >> $HOME/.zshrc

eval "$(pyenv init - bash)"

pyenv install 3.10.18
pyenv global 3.10.18

source $HOME/.zshrc

sudo rm -r /usr/local/go
curl -L go.dev/dl/$(curl https://go.dev/dl/\?mode=json | jq -r '.[0].version').linux-$(dpkg --print-architecture).tar.gz --output /tmp/go.tar.gz && sudo tar -C /usr/local -xzf /tmp/go.tar.gz
/usr/local/go/bin/go install github.com/go-delve/delve/cmd/dlv@latest

cd $HOME
mkdir .config
cd $HOME/.config
git clone https://github.com/sergeybrian/nvim

curl https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip --output /tmp/JetBrainsMono.zip 
unzip /tmp/JetBrainsMono.zip -d $HOME/.local/share/fonts


for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

