# 自用配置文件备份

## 使用

```bash
git clone https://github.com/YangRucheng/Config-Backup.git temp-dir # 克隆仓库
rm -rf temp-dir/.git # 删除Git文件夹
find temp-dir -name "*.md" -exec rm -f {} \;  # 删除多余文件
mv temp-dir/.* temp-dir/* . 2>/dev/null # 移动到当前目录
rm -r temp-dir  # 删除临时目录
```