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
        KERNELPATCHDIR=$(grep -E '^\s*KERNELPATCHDIR=' "${FAMILY_CONF}" | tail -1 | sed -E 's/^[^=]*=\s*//; s/\s*#.*//; s/["'"'"'"]//g')
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



# 自定义版本号（基于日期）
echo "$(date +%y).$(date +%m).1" > VERSION

echo "==> Patches applied successfully."
