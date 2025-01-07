#! /bin/bash

# 克隆仓库
git clone https://github.com/YangRucheng/Config-Backup.git temp-dir

# 移动文件
shopt -s dotglob
cp -r temp-dir/resource/* ~/
rm -rf temp-dir

# 设置 SSH
chmod 600 ~/.ssh
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config
# sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config

# 结束
echo "Success! 执行成功！"