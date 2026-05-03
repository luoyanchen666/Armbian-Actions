#!/bin/bash
set -euo pipefail

echo "==> Applying custom patches..."

# 1. 应用全局通用补丁（配置、板子、sbin）
echo "    Copying global config/boards/sbin patches..."
mkdir -p config/kernel config/boards packages/bsp/common/usr/sbin
[ -d "${GITHUB_WORKSPACE}/patch-overlay/common/config" ] && \
    cp -f "${GITHUB_WORKSPACE}/patch-overlay/common/config/"* config/kernel/ 2>/dev/null || true
[ -d "${GITHUB_WORKSPACE}/patch-overlay/common/boards" ] && \
    cp -f "${GITHUB_WORKSPACE}/patch-overlay/common/boards/"* config/boards/ 2>/dev/null || true
if [[ "${RELEASE}" =~ ^(bookworm|trixie)$ ]]; then
    [ -d "${GITHUB_WORKSPACE}/patch-overlay/common/sbin" ] && \
        rsync -a --quiet "${GITHUB_WORKSPACE}/patch-overlay/common/sbin/" packages/bsp/common/usr/sbin/
else
    [ -d "${GITHUB_WORKSPACE}/patch-overlay/common/sbin" ] && \
        rsync -a --quiet --exclude='install-pve' "${GITHUB_WORKSPACE}/patch-overlay/common/sbin/" packages/bsp/common/usr/sbin/
fi

# 2. 应用特定板子/家族的内核补丁
#    先获取目标板的家族名称（BOARDFAMILY）
BOARDFAMILY=""
BOARD_CONF=$(find config/boards/ -maxdepth 1 -name "${BOARD}.*" 2>/dev/null | head -1)
if [ -n "${BOARD_CONF}" ]; then
    BOARDFAMILY=$(grep -E '^\s*BOARDFAMILY=' "${BOARD_CONF}" | tail -1 | sed 's/^[^=]*=\s*["'"'"']\?//;s/["'"'"']\?$//')
fi

if [ -z "${BOARDFAMILY}" ]; then
    echo "    WARNING: Could not determine BOARDFAMILY for ${BOARD}, skipping kernel patches."
else
    echo "    Board family detected: ${BOARDFAMILY}"
    # 从家族配置文件获取 KERNELPATCHDIR
    KERNELPATCHDIR=""
    FAMILY_CONF="config/sources/families/${BOARDFAMILY}.conf"
    if [ -f "${FAMILY_CONF}" ]; then
        KERNELPATCHDIR=$(grep -E '^\s*KERNELPATCHDIR=' "${FAMILY_CONF}" | tail -1 | sed 's/^[^=]*=\s*["'"'"']\?//;s/["'"'"']\?$//')
    fi

    # 有时 KERNELPATCHDIR 定义在 include 文件中，做一次动态搜索
    if [ -z "${KERNELPATCHDIR}" ]; then
        KERNELPATCHDIR=$(find config/sources/families/include/ -type f -name "${BOARDFAMILY}*.inc" -exec grep -l "KERNELPATCHDIR" {} \; | xargs -r grep "KERNELPATCHDIR" | tail -1 | sed 's/^.*KERNELPATCHDIR=//;s/[[:space:]]*#.*//' | tr -d '"'"'"' || true)
    fi

    if [ -z "${KERNELPATCHDIR}" ]; then
        echo "    WARNING: Could not find KERNELPATCHDIR for family ${BOARDFAMILY}, skipping kernel patches."
    else
        echo "    KERNELPATCHDIR resolved to: ${KERNELPATCHDIR}"
        TARGET_PATCH_DIR="patch/kernel/${KERNELPATCHDIR}"
        mkdir -p "${TARGET_PATCH_DIR}"

        # 从仓库 patch-overlay/<家族>/<分支>/ 复制补丁
        OVERLAY_SRC="${GITHUB_WORKSPACE}/patch-overlay/${BOARDFAMILY}/${BRANCH}"
        if [ -d "${OVERLAY_SRC}" ]; then
            echo "    Copying kernel patches from ${OVERLAY_SRC} to ${TARGET_PATCH_DIR}"
            cp -f "${OVERLAY_SRC}"/* "${TARGET_PATCH_DIR}/" 2>/dev/null || true

            # 如果补丁资源中包含 dt 子目录，也一并复制
            if [ -d "${OVERLAY_SRC}/dt" ]; then
                rm -rf "${TARGET_PATCH_DIR}/dt" 2>/dev/null || true
                cp -r "${OVERLAY_SRC}/dt" "${TARGET_PATCH_DIR}/dt"
            fi
        else
            echo "    No kernel patches found for ${BOARDFAMILY}/${BRANCH} in patch-overlay, skipping."
        fi
    fi
fi

# 3. 处理特殊的 flippy / legacy 分支（保留原逻辑，但修正补丁目标路径）
if [[ "${BRANCH}" == "flippy" ]]; then
    echo "    Adding flippy branch definitions..."
    sed -i '0,/case \$BRANCH in/{
        /case \$BRANCH in/a\
        flippy)\
            BOOTSCRIPT='"'"'boot-rk35xx.cmd:boot.cmd'"'"'\
            BOOTDIR='"'"'u-boot-rockchip64'"'"'\
            declare -g KERNEL_MAJOR_MINOR="6.1"\
            declare -g -i KERNEL_GIT_CACHE_TTL=120\
            KERNELSOURCE='"'"'https://github.com/unifreq/linux-6.1.y-rockchip.git'"'"'\
            KERNELBRANCH='"'"'branch:main'"'"'\
            KERNELPATCHDIR='"'"'rk35xx-vendor-6.1'"'"'\
            ;;
    }' config/sources/families/rk35xx.conf

    sed -i '0,/case \$BRANCH in/{
        /case \$BRANCH in/a\
        flippy)\
            BOOTSCRIPT='"'"'boot-rk35xx.cmd:boot.cmd'"'"'\
            BOOTDIR='"'"'u-boot-rockchip64'"'"'\
            declare -g KERNEL_MAJOR_MINOR="6.1"\
            declare -g -i KERNEL_GIT_CACHE_TTL=120\
            KERNELSOURCE='"'"'https://github.com/unifreq/linux-6.1.y-rockchip.git'"'"'\
            KERNELBRANCH='"'"'branch:main'"'"'\
            KERNELPATCHDIR='"'"'rk35xx-vendor-6.1'"'"'\
            LINUXFAMILY=rk35xx\
            ;;
    }' config/sources/families/rockchip-rk3588.conf

    sed -i '0,/case \$BRANCH in/{
        /case \$BRANCH in/a\
        flippy)\
            declare -g KERNEL_MAJOR_MINOR="6.18"\
            declare -g -i KERNEL_GIT_CACHE_TTL=120\
            KERNELSOURCE='"'"'https://github.com/unifreq/linux-6.18.y.git'"'"'\
            KERNELBRANCH='"'"'branch:main'"'"'\
            KERNELPATCHDIR='"'"'meson64-6.18'"'"'\
            ;;
    }' config/sources/families/include/meson64_common.inc

    sed -i '0,/case \$BRANCH in/{
        /case \$BRANCH in/a\
        flippy)\
            declare -g KERNEL_MAJOR_MINOR="6.18"\
            declare -g -i KERNEL_GIT_CACHE_TTL=120\
            KERNELSOURCE='"'"'https://github.com/unifreq/linux-6.18.y.git'"'"'\
            KERNELBRANCH='"'"'branch:main'"'"'\
            KERNELPATCHDIR='"'"'rockchip64-6.18'"'"'\
            ;;
    }' config/sources/families/include/rockchip64_common.inc

    # 复制 flippy 分支专用补丁（现在直接进入对应的 KERNELPATCHDIR 目录）
    mkdir -p patch/kernel/rk35xx-vendor-6.1
    cp -f "${GITHUB_WORKSPACE}/patch/test/flippy/config/"* config/kernel/ 2>/dev/null || true
    # 如果你还有其他 flippy 内核补丁，请把它们从 patch-overlay 对应的位置复制过来，
    # 但最好预先放到 patch-overlay/rk35xx/vendor/ 等标准位置（见后续建议）。

elif [[ "${BRANCH}" == "legacy" ]]; then
    echo "    Adding legacy branch definitions..."
    sed -i '0,/case \$BRANCH in/{
        /case \$BRANCH in/a\
        legacy)\
            declare -g KERNEL_MAJOR_MINOR="6.12"\
            KERNELPATCHDIR='"'"'meson64-6.12'"'"'\
            ;;
    }' config/sources/families/include/meson64_common.inc

    sed -i '0,/case \$BRANCH in/{
        /case \$BRANCH in/a\
        legacy)\
            declare -g KERNEL_MAJOR_MINOR="6.12"\
            LINUXFAMILY=rockchip64\
            LINUXCONFIG='"'"'linux-rockchip64-'"'"'$BRANCH\
            KERNELPATCHDIR='"'"'rockchip64-6.12'"'"'\
            ;;
    }' config/sources/families/include/rockchip64_common.inc

    # 将 legacy 补丁复制到刚刚声明过的 KERNELPATCHDIR 下
    mkdir -p patch/kernel/meson64-6.12 patch/kernel/rockchip64-6.12
    cp -f "${GITHUB_WORKSPACE}/patch/N1/fix-n1-"*.patch patch/kernel/meson64-6.12/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/T4/t4.patch" patch/kernel/rockchip64-6.12/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information.patch" patch/kernel/rockchip64-6.12/ 2>/dev/null || true
    [ -d patch/kernel/rockchip64-6.12/dt ] || mkdir -p patch/kernel/rockchip64-6.12/dt
    cp -f "${GITHUB_WORKSPACE}/patch/JP/rk3566-jp-tvbox.dts" patch/kernel/rockchip64-6.12/dt/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/X2/rk3566-panther-x2.dts" patch/kernel/rockchip64-6.12/dt/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/test/legacy/rockchip64/"* patch/kernel/rockchip64-6.12/ 2>/dev/null || true
    rm -f patch/kernel/rockchip64-6.12/board-pbp-add-dp-alt-mode.patch
    rm -f patch/kernel/rockchip64-6.12/rk3308-i2s-default-rate.patch
    cp -f "${GITHUB_WORKSPACE}/patch/test/legacy/config/"* config/kernel/ 2>/dev/null || true
fi

# 4. 保留其他原脚本中仍然有效的补丁复制（但已经用上面的自动化逻辑覆盖了很多）
#    以下补丁仍直接复制，但可考虑逐步迁移到 patch-overlay
# T4 patches
echo "    Copying T4 patches..."
mkdir -p patch/kernel/rockchip64-6.18 patch/kernel/rockchip64-7.0
cp -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information-6.16.patch" patch/kernel/rockchip64-6.18/ 2>/dev/null || true
cp -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information-6.16.patch" patch/kernel/rockchip64-7.0/ 2>/dev/null || true
cp -f "${GITHUB_WORKSPACE}/patch/T4/t4.patch" patch/kernel/rockchip64-6.18/ 2>/dev/null || true
cp -f "${GITHUB_WORKSPACE}/patch/T4/t4.patch" patch/kernel/rockchip64-7.0/ 2>/dev/null || true

# 5C patches
echo "    Copying 5C patches..."
mkdir -p patch/u-boot/legacy/u-boot-radxa-rk35xx/board_rock-5c
cp -f "${GITHUB_WORKSPACE}/patch/5C/reopen_disabled_nodes.patch" patch/u-boot/legacy/u-boot-radxa-rk35xx/board_rock-5c/ 2>/dev/null || true
mkdir -p patch/kernel/rk35xx-vendor-6.1
cp -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information.patch" patch/kernel/rk35xx-vendor-6.1/ 2>/dev/null || true
cp -f "${GITHUB_WORKSPACE}/patch/5C/diyfan-5c.patch" patch/kernel/rk35xx-vendor-6.1/ 2>/dev/null || true

# 5T patches
echo "    Copying 5T patches..."
cp -f "${GITHUB_WORKSPACE}/patch/5T/"* patch/kernel/rk35xx-vendor-6.1/ 2>/dev/null || true
sed -i 's|https://github.com/armbian/linux-rockchip.git|https://github.com/zane-e/linux-rockchip.git|g' config/sources/families/rk35xx.conf
sed -i 's|https://github.com/armbian/linux-rockchip.git|https://github.com/zane-e/linux-rockchip.git|g' config/sources/families/rockchip-rk3588.conf

# N1 patches
echo "    Copying N1 patches..."
mkdir -p patch/kernel/meson64-6.18 patch/kernel/meson64-7.0
cp -f "${GITHUB_WORKSPACE}/patch/N1/fix-n1-"*.patch patch/kernel/meson64-6.18/ 2>/dev/null || true
cp -f "${GITHUB_WORKSPACE}/patch/N1/fix-n1-"*.patch patch/kernel/meson64-7.0/ 2>/dev/null || true
mkdir -p config/optional/boards/aml-s9xx-box/_packages/bsp-cli/boot
cp -f "${GITHUB_WORKSPACE}/patch/N1/u-boot.ext" config/optional/boards/aml-s9xx-box/_packages/bsp-cli/boot/ 2>/dev/null || true

# X2 patches
echo "    Copying X2 patches..."
cp -f "${GITHUB_WORKSPACE}/patch/X2/rk3566-panther-x2.dts" patch/kernel/rockchip64-6.18/dt/ 2>/dev/null || true
cp -f "${GITHUB_WORKSPACE}/patch/X2/rk3566-panther-x2.dts" patch/kernel/rockchip64-7.0/dt/ 2>/dev/null || true
[ -d patch/kernel/rk35xx-vendor-6.1/dt ] || mkdir -p patch/kernel/rk35xx-vendor-6.1/dt
cp -r "${GITHUB_WORKSPACE}/patch/X2/dt/"* patch/kernel/rk35xx-vendor-6.1/dt/ 2>/dev/null || true

# JP patches
echo "    Copying JP patches..."
cp -f "${GITHUB_WORKSPACE}/patch/JP/rk3566-jp-tvbox.dts" patch/kernel/rockchip64-6.18/dt/ 2>/dev/null || true
cp -f "${GITHUB_WORKSPACE}/patch/JP/rk3566-jp-tvbox.dts" patch/kernel/rockchip64-7.0/dt/ 2>/dev/null || true
cp -f "${GITHUB_WORKSPACE}/patch/JP/dt/rk3566-jp-tvbox.dts" patch/kernel/rk35xx-vendor-6.1/dt/ 2>/dev/null || true

# 5. 全局的脚本/配置修改（保留你原来所有的 sed 改动）
sed -i '28s/^/#/' config/sources/families/include/meson_common.inc
rm -f patch/kernel/archive/meson-6.12/0052-drm-meson-Describe-the-HDMI-PHY-frequency-limits-of-.patch

sed -i 's|Armbian-unofficial|Armbian|g' lib/functions/configuration/main-config.sh
sed -i 's|LOCALVERSION=-${BRANCH}-${LINUXFAMILY}|LOCALVERSION=|g' lib/functions/compilation/kernel-make.sh
sed -i 's|${kernel_version}-${BRANCH}-${LINUXFAMILY}|${kernel_version}|g' lib/functions/compilation/kernel-debs.sh
sed -i 's|linux-image-${BRANCH}-${LINUXFAMILY}|linux-image-${LINUXFAMILY}|g' lib/functions/compilation/kernel-debs.sh
sed -i 's|linux-dtb-${BRANCH}-${LINUXFAMILY}|linux-dtb-${LINUXFAMILY}|g' lib/functions/compilation/kernel-debs.sh
sed -i 's|linux-headers-${BRANCH}-${LINUXFAMILY}|linux-headers-${LINUXFAMILY}|g' lib/functions/compilation/kernel-debs.sh
sed -i 's|linux-libc-dev-${BRANCH}-${LINUXFAMILY}|linux-libc-dev-${LINUXFAMILY}|g' lib/functions/compilation/kernel-debs.sh
sed -i 's|linux-image-${BRANCH}-${LINUXFAMILY}|linux-image-${LINUXFAMILY}|g' lib/functions/artifacts/artifact-kernel.sh
sed -i 's|linux-dtb-${BRANCH}-${LINUXFAMILY}|linux-dtb-${LINUXFAMILY}|g' lib/functions/artifacts/artifact-kernel.sh
sed -i 's|linux-headers-${BRANCH}-${LINUXFAMILY}|linux-headers-${LINUXFAMILY}|g' lib/functions/artifacts/artifact-kernel.sh
sed -i 's|linux-libc-dev-${BRANCH}-${LINUXFAMILY}|linux-libc-dev-${LINUXFAMILY}|g' lib/functions/artifacts/artifact-kernel.sh
sed -i 's|IMAGE_TYPE=user-built|IMAGE_TYPE=stable|g' lib/functions/main/config-prepare.sh
sed -i 's|1800000|1992000|g' config/sources/families/include/rockchip64_common.inc

sed -i '252{/else/s/^/#/}' lib/functions/cli/utils-cli.sh
sed -i '253{/display_alert/s/^/#/}' lib/functions/cli/utils-cli.sh
sed -i '272{/display_alert/s/^/#/}' lib/functions/cli/utils-cli.sh
sed -i '398{/display_alert/s/^/#/}' lib/functions/main/config-prepare.sh

echo "$(date +%y).$(date +%m).1" > VERSION

echo "==> Patches applied successfully."
