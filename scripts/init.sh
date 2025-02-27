#! /bin/bash

URL="https://cdn.jsdelivr.net/gh/YangRucheng/Config-Backup@main/resource"

wget --tries=10 -O ~/.bashrc "$URL/.bashrc"
wget --tries=10 -O ~/.npmrc "$URL/.npmrc"
wget --tries=10 -O ~/.tmux.conf "$URL/.tmux.conf"
wget --tries=10 -O ~/.bash_profile "$URL/.bash_profile"
source ~/.bashrc && echo "Host" > /etc/hostname && hostname Host


mkdir -p ~/.ssh && chmod 600 ~/.ssh
wget --tries=10 -O ~/.ssh/authorized_keys "$URL/.ssh/authorized_keys"
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config

mkdir -p /etc/docker
wget --tries=10 -O /etc/docker/daemon.json "$URL/daemon.json"

echo "Success! 执行成功！"