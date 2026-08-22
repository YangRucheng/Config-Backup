#! /bin/bash

apt install -y fonts-wqy-zenhei && fc-cache
sed -i 's/^# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=zh_CN.UTF-8' > /etc/default/locale
