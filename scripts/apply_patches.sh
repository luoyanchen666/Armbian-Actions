#!/bin/bash
set -euo pipefail

echo "==> Applying custom patches..."

# ==============================================
# 1. 全局通用补丁（配置、板子、sbin）
# ==============================================
echo "    Copying global config/boards/sbin patches..."
mkdir -p config/kernel config/boards packages/bsp/common/usr/sbin

if [ -d "${GITHUB_WORKSPACE}/patch-overlay/common/config" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch-overlay/common/config/"* config/kernel/ 2>/dev/null || true
fi
if [ -d "${GITHUB_WORKSPACE}/patch-overlay/common/boards" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch-overlay/common/boards/"* config/boards/ 2>/dev/null || true
fi
if [ -d "${GITHUB_WORKSPACE}/patch-overlay/common/sbin" ]; then
    if [[ "${RELEASE}" =~ ^(bookworm|trixie)$ ]]; then
        rsync -a --quiet "${GITHUB_WORKSPACE}/patch-overlay/common/sbin/" packages/bsp/common/usr/sbin/
    else
        rsync -a --quiet --exclude='install-pve' "${GITHUB_WORKSPACE}/patch-overlay/common/sbin/" packages/bsp/common/usr/sbin/
    fi
fi

# ==============================================
# 2. 自动检测板子家族及内核补丁目录
# ==============================================
BOARDFAMILY=""
BOARD_CONF=$(find config/boards/ -maxdepth 1 -name "${BOARD}.*" 2>/dev/null | head -1)
if [ -n "${BOARD_CONF}" ]; then
    BOARDFAMILY=$(grep -E '^\s*BOARDFAMILY=' "${BOARD_CONF}" | tail -1 | sed 's/^[^=]*=\s*["'"'"']\?//;s/["'"'"']\?$//')
fi

if [ -z "${BOARDFAMILY}" ]; then
    echo "    WARNING: Could not determine BOARDFAMILY for ${BOARD}, skipping family-based patches."
else
    echo "    Board family detected: ${BOARDFAMILY}"

    # 尝试从家族主配置文件获取初始 KERNELPATCHDIR
    KERNELPATCHDIR=""
    FAMILY_CONF="config/sources/families/${BOARDFAMILY}.conf"
    if [ -f "${FAMILY_CONF}" ]; then
        KERNELPATCHDIR=$(grep -E '^\s*KERNELPATCHDIR=' "${FAMILY_CONF}" | tail -1 | sed 's/^[^=]*=\s*["'"'"']\?//;s/["'"'"']\?$//')
    fi

    # 如果没找到，再搜索 include 文件
    if [ -z "${KERNELPATCHDIR}" ]; then
        KERNELPATCHDIR=$(find config/sources/families/include/ -type f -name "${BOARDFAMILY}*.inc" -exec grep -l "KERNELPATCHDIR" {} \; | xargs -r grep "KERNELPATCHDIR" | tail -1 | sed 's/^.*KERNELPATCHDIR=//;s/[[:space:]]*#.*//' | tr -d '"'"'"' || true)
    fi

    if [ -z "${KERNELPATCHDIR}" ]; then
        echo "    WARNING: Could not find KERNELPATCHDIR for family ${BOARDFAMILY}, skipping kernel patches."
    else
        echo "    KERNELPATCHDIR resolved to: ${KERNELPATCHDIR}"
        TARGET_PATCH_DIR="patch/kernel/${KERNELPATCHDIR}"
        mkdir -p "${TARGET_PATCH_DIR}"

        # 从 patch-overlay 复制内核补丁
        OVERLAY_SRC="${GITHUB_WORKSPACE}/patch-overlay/${BOARDFAMILY}/${BRANCH}"
        if [ -d "${OVERLAY_SRC}" ]; then
            echo "    Copying kernel patches from ${OVERLAY_SRC} to ${TARGET_PATCH_DIR}"
            cp -f "${OVERLAY_SRC}/"*.patch "${TARGET_PATCH_DIR}/" 2>/dev/null || true

            # 复制 dt 子目录（设备树文件）
            if [ -d "${OVERLAY_SRC}/dt" ]; then
                rm -rf "${TARGET_PATCH_DIR}/dt" 2>/dev/null || true
                cp -r "${OVERLAY_SRC}/dt" "${TARGET_PATCH_DIR}/dt"
            fi
        else
            echo "    No overlay patches found for ${BOARDFAMILY}/${BRANCH}, skipping."
        fi
    fi
fi

# ==============================================
# 3. 特殊分支处理（flippy / legacy）
#    保留原有 sed 添加逻辑，但修正补丁目标路径为 KERNELPATCHDIR
# ==============================================
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

    # 确保对应的补丁目录存在
    mkdir -p patch/kernel/rk35xx-vendor-6.1
    # 如果你有 flippy 专用的 config 补丁，保留原逻辑
    if [ -d "${GITHUB_WORKSPACE}/patch/test/flippy/config" ]; then
        cp -f "${GITHUB_WORKSPACE}/patch/test/flippy/config/"* config/kernel/ 2>/dev/null || true
    fi
    # 注意：flippy 内核补丁现在应该放在 patch-overlay 下的对应位置（例如 rk35xx/vendor），
    # 上面第2步的自动复制已经覆盖了这部分，所以不再需要手动复制内核补丁到 patch/kernel 了。

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

    # 创建正确的补丁目录并复制旧有的 legacy 补丁（从原 patch/ 目录）
    mkdir -p patch/kernel/meson64-6.12
    mkdir -p patch/kernel/rockchip64-6.12/dt

    if [ -d "${GITHUB_WORKSPACE}/patch/N1" ]; then
        cp -f "${GITHUB_WORKSPACE}/patch/N1/fix-n1-"*.patch patch/kernel/meson64-6.12/ 2>/dev/null || true
    fi
    if [ -f "${GITHUB_WORKSPACE}/patch/T4/t4.patch" ]; then
        cp -f "${GITHUB_WORKSPACE}/patch/T4/t4.patch" patch/kernel/rockchip64-6.12/ 2>/dev/null || true
    fi
    if [ -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information.patch" ]; then
        cp -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information.patch" patch/kernel/rockchip64-6.12/ 2>/dev/null || true
    fi
    if [ -f "${GITHUB_WORKSPACE}/patch/JP/rk3566-jp-tvbox.dts" ]; then
        cp -f "${GITHUB_WORKSPACE}/patch/JP/rk3566-jp-tvbox.dts" patch/kernel/rockchip64-6.12/dt/ 2>/dev/null || true
    fi
    if [ -f "${GITHUB_WORKSPACE}/patch/X2/rk3566-panther-x2.dts" ]; then
        cp -f "${GITHUB_WORKSPACE}/patch/X2/rk3566-panther-x2.dts" patch/kernel/rockchip64-6.12/dt/ 2>/dev/null || true
    fi
    if [ -d "${GITHUB_WORKSPACE}/patch/test/legacy/rockchip64" ]; then
        cp -f "${GITHUB_WORKSPACE}/patch/test/legacy/rockchip64/"* patch/kernel/rockchip64-6.12/ 2>/dev/null || true
    fi
    # 删除不需要的官方补丁
    rm -f patch/kernel/rockchip64-6.12/board-pbp-add-dp-alt-mode.patch
    rm -f patch/kernel/rockchip64-6.12/rk3308-i2s-default-rate.patch

    if [ -d "${GITHUB_WORKSPACE}/patch/test/legacy/config" ]; then
        cp -f "${GITHUB_WORKSPACE}/patch/test/legacy/config/"* config/kernel/ 2>/dev/null || true
    fi
fi

# ==============================================
# 4. 接下来是硬编码的板子补丁（T4, N1, X2, JP 等）
#    这些补丁直接复制到已知的内核补丁目录，
#    你可以选择保留，或逐步迁移到 patch-overlay 中。
# ==============================================

# T4 patches (针对 rockchip64 的 6.18 和 7.0 分支)
echo "    Copying T4 patches..."
mkdir -p patch/kernel/rockchip64-6.18 patch/kernel/rockchip64-7.0
if [ -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information-6.16.patch" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information-6.16.patch" patch/kernel/rockchip64-6.18/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information-6.16.patch" patch/kernel/rockchip64-7.0/ 2>/dev/null || true
fi
if [ -f "${GITHUB_WORKSPACE}/patch/T4/t4.patch" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/T4/t4.patch" patch/kernel/rockchip64-6.18/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/T4/t4.patch" patch/kernel/rockchip64-7.0/ 2>/dev/null || true
fi

# 5C patches
echo "    Copying 5C patches..."
mkdir -p patch/u-boot/legacy/u-boot-radxa-rk35xx/board_rock-5c
if [ -f "${GITHUB_WORKSPACE}/patch/5C/reopen_disabled_nodes.patch" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/5C/reopen_disabled_nodes.patch" patch/u-boot/legacy/u-boot-radxa-rk35xx/board_rock-5c/ 2>/dev/null || true
fi
mkdir -p patch/kernel/rk35xx-vendor-6.1
if [ -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information.patch" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/T4/fix-CPU-information.patch" patch/kernel/rk35xx-vendor-6.1/ 2>/dev/null || true
fi
if [ -f "${GITHUB_WORKSPACE}/patch/5C/diyfan-5c.patch" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/5C/diyfan-5c.patch" patch/kernel/rk35xx-vendor-6.1/ 2>/dev/null || true
fi

# 5T patches
echo "    Copying 5T patches..."
if [ -d "${GITHUB_WORKSPACE}/patch/5T" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/5T/"* patch/kernel/rk35xx-vendor-6.1/ 2>/dev/null || true
fi
sed -i 's|https://github.com/armbian/linux-rockchip.git|https://github.com/zane-e/linux-rockchip.git|g' config/sources/families/rk35xx.conf
sed -i 's|https://github.com/armbian/linux-rockchip.git|https://github.com/zane-e/linux-rockchip.git|g' config/sources/families/rockchip-rk3588.conf

# N1 patches
echo "    Copying N1 patches..."
mkdir -p patch/kernel/meson64-6.18 patch/kernel/meson64-7.0
if [ -d "${GITHUB_WORKSPACE}/patch/N1" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/N1/fix-n1-"*.patch patch/kernel/meson64-6.18/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/N1/fix-n1-"*.patch patch/kernel/meson64-7.0/ 2>/dev/null || true
    mkdir -p config/optional/boards/aml-s9xx-box/_packages/bsp-cli/boot
    cp -f "${GITHUB_WORKSPACE}/patch/N1/u-boot.ext" config/optional/boards/aml-s9xx-box/_packages/bsp-cli/boot/ 2>/dev/null || true
fi

# X2 patches
echo "    Copying X2 patches..."
mkdir -p patch/kernel/rockchip64-6.18/dt patch/kernel/rockchip64-7.0/dt
if [ -f "${GITHUB_WORKSPACE}/patch/X2/rk3566-panther-x2.dts" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/X2/rk3566-panther-x2.dts" patch/kernel/rockchip64-6.18/dt/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/X2/rk3566-panther-x2.dts" patch/kernel/rockchip64-7.0/dt/ 2>/dev/null || true
fi
mkdir -p patch/kernel/rk35xx-vendor-6.1/dt
if [ -d "${GITHUB_WORKSPACE}/patch/X2/dt" ]; then
    cp -r "${GITHUB_WORKSPACE}/patch/X2/dt/"* patch/kernel/rk35xx-vendor-6.1/dt/ 2>/dev/null || true
fi

# JP patches
echo "    Copying JP patches..."
if [ -f "${GITHUB_WORKSPACE}/patch/JP/rk3566-jp-tvbox.dts" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/JP/rk3566-jp-tvbox.dts" patch/kernel/rockchip64-6.18/dt/ 2>/dev/null || true
    cp -f "${GITHUB_WORKSPACE}/patch/JP/rk3566-jp-tvbox.dts" patch/kernel/rockchip64-7.0/dt/ 2>/dev/null || true
fi
if [ -f "${GITHUB_WORKSPACE}/patch/JP/dt/rk3566-jp-tvbox.dts" ]; then
    cp -f "${GITHUB_WORKSPACE}/patch/JP/dt/rk3566-jp-tvbox.dts" patch/kernel/rk35xx-vendor-6.1/dt/ 2>/dev/null || true
fi

# ==============================================
# 5. 全局构建脚本 / 配置的修改（原脚本后半部分）
# ==============================================
echo "    Applying global build script modifications..."

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

# 自定义版本号（基于日期）
echo "$(date +%y).$(date +%m).1" > VERSION

echo "==> Patches applied successfully."
