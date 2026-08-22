#! /bin/bash
set -euo pipefail

URL="https://gitee.com/YangRucheng/Config-Backup/raw/main/resource"

# 静默下载：-q 关闭进度条、网络重定向等冗余输出，只保留错误信息
fetch() {
  wget -q --tries=10 -O "$2" "$1" || {
    echo "[!] 下载失败: $1" >&2
    exit 1
  }
}

echo "==> 下载常用配置文件"
fetch "$URL/.npmrc" ~/.npmrc
fetch "$URL/.bashrc" ~/.bashrc
fetch "$URL/.tmux.conf" ~/.tmux.conf
fetch "$URL/.bash_profile" ~/.bash_profile
echo "    完成: ~/.npmrc ~/.bashrc ~/.tmux.conf ~/.bash_profile"

echo "==> 安装 Docker 配置"
mkdir -p /etc/docker
fetch "$URL/daemon.json" /etc/docker/daemon.json
echo "    完成: /etc/docker/daemon.json"

echo "==> 安装 Maven 配置"
mkdir -p ~/.m2
fetch "$URL/.m2/settings.xml" ~/.m2/settings.xml
echo "    完成: ~/.m2/settings.xml"

echo "==> 安装 SSH 公钥"
mkdir -p ~/.ssh
chmod 600 ~/.ssh
fetch "$URL/.ssh/authorized_keys" ~/.ssh/authorized_keys
echo "    完成: ~/.ssh/authorized_keys"

echo "==> 设置主机名"
source ~/.bashrc
echo "Host" > /etc/hostname
hostname Host
# 写入主机名解析（127.0.1.1 是 Debian/Ubuntu 的主机名解析惯例）
sed -i "/^127\.0\.1\.1[[:space:]]\+/d" /etc/hosts
echo "127.0.1.1 Host" >> /etc/hosts
echo "    完成: 主机名已设置为 Host，并写入 /etc/hosts 解析"

echo "==> 配置 SSH 允许 root 公钥登录"
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config
echo "    完成: /etc/ssh/sshd_config 已更新"

echo "Success! 执行成功！"
