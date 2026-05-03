#!/bin/bash

# =================================================================
# 1. 安装自定义设备树覆盖层
# =================================================================
cp /tmp/overlay/my-overlay.dts /root/
chroot . /bin/bash -c "armbian-add-overlay /root/my-overlay.dts"
rm /root/my-overlay.dts

# =================================================================
# 2. 更换 APT 源为阿里云镜像（优先使用 DEB822 .sources 格式）
# =================================================================

# 获取系统信息
os_id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
codename=$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')

# 定义阿里云镜像基地址
if [ "$os_id" = "debian" ]; then
    mirror_base="http://mirrors.aliyun.com/debian"
    security_mirror="http://mirrors.aliyun.com/debian-security"
elif [ "$os_id" = "ubuntu" ]; then
    mirror_base="http://mirrors.aliyun.com/ubuntu"
    # Ubuntu 安全更新通常也在同一镜像下
    security_mirror="http://mirrors.aliyun.com/ubuntu"
else
    echo "Unsupported OS: $os_id, skip mirror change"
    exit 0
fi

# 检查是否存在 .sources 文件（DEB822 格式）
sources_files=$(find /etc/apt/sources.list.d/ -maxdepth 1 -name '*.sources' 2>/dev/null | wc -l)

if [ "$sources_files" -gt 0 ]; then
    echo "Found .sources files, switching to Aliyun mirrors using DEB822 format..."
    
    # 遍历所有 .sources 文件，替换 URI
    for f in /etc/apt/sources.list.d/*.sources; do
        # 替换 Debian 官方镜像
        sed -i "s|http://deb.debian.org/debian|$mirror_base|g" "$f"
        sed -i "s|http://security.debian.org/debian-security|$security_mirror|g" "$f"
        # 替换 Ubuntu 官方镜像
        sed -i "s|http://archive.ubuntu.com/ubuntu|$mirror_base|g" "$f"
        sed -i "s|http://ports.ubuntu.com/ubuntu-ports|$mirror_base|g" "$f"
        sed -i "s|http://security.ubuntu.com/ubuntu|$security_mirror|g" "$f"
    done
else
    # 没有 .sources 文件，回退处理传统 /etc/apt/sources.list
    echo "No .sources files found, falling back to classic sources.list..."
    
    # 先禁用所有旧的 .list 文件（防止重复）
    mv /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
    find /etc/apt/sources.list.d/ -name '*.list' -exec mv {} {}.disabled \; 2>/dev/null || true
    
    # 写入新的 .list（传统格式）
    if [ "$os_id" = "debian" ]; then
        cat > /etc/apt/sources.list <<EOF
deb $mirror_base $codename main contrib non-free non-free-firmware
deb $mirror_base $codename-updates main contrib non-free non-free-firmware
deb $security_mirror $codename-security main contrib non-free non-free-firmware
EOF
    elif [ "$os_id" = "ubuntu" ]; then
        cat > /etc/apt/sources.list <<EOF
deb $mirror_base $codename main restricted universe multiverse
deb $mirror_base $codename-updates main restricted universe multiverse
deb $security_mirror $codename-security main restricted universe multiverse
deb $mirror_base $codename-backports main restricted universe multiverse
EOF
    fi
fi

echo "APT sources updated to Aliyun mirrors."
