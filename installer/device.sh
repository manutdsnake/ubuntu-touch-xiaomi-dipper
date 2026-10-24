# Device settings for install.sh - Xiaomi Mi 8 (dipper).

NAME="Xiaomi Mi 8"
CODENAME="dipper"
REPO="manutdsnake/ubuntu-touch-xiaomi-dipper"
# /proc/device-tree/model in recovery, e.g. "Xiaomi Technologies, Inc. Dipper new MP v2.1"
DT_MODEL_MATCH="dipper"

# Flashed with fastboot to get into the UBports recovery.
RECOVERY_IMAGES=(recovery.img)

# The Android base the port runs on, written from recovery as
# "file partition offset" (offset in 4096-byte blocks):
# - the LP metadata of the retrofit super (system 4 GiB, vendor, odm spread
#   over the physical system, vendor and cust partitions) at the start of the
#   physical system partition;
# - vendor and odm of LineageOS 22.2 (lineage-22.2-20260919-nightly-dipper)
#   where that metadata places them (vendor: system @ sector 2163488,
#   odm: cust @ sector 25984);
# - LineageOS' vbmeta.
BASE=(
    "lp-metadata.img system 0"
    "vendor.img system 270436"
    "odm.img cust 3248"
    "vbmeta.img vbmeta 0"
)

# Firmware: MIUI V12.5.2.0.QEACNXM (Android 10), the firmware LineageOS 22.2
# asserts. Checked partition by partition; only downloaded and flashed when
# something differs. Mapping as MIUI's own updater-script (slot a, abl on both).
FIRMWARE_NAME="MIUI V12.5.2.0.QEACNXM firmware"
FIRMWARE_URL="https://bn.d.miui.com/V12.5.2.0.QEACNXM/miui_MI8_V12.5.2.0.QEACNXM_f5ec813d1c_10.0.zip"
FIRMWARE_SHA256="9246e42d051f8aed76a86f7038e23e0faad8b1220da12431ef4578dc8f8c0038"
FIRMWARE_ARCHIVE="zip"
FIRMWARE_SIZE="2.2 GB"
#   "partition member-in-archive size sha256"
FIRMWARE=(
    "abl_a firmware-update/abl.elf 155648 7c906fd151b4f12b54fa53a93ae7aef7afe1c8227e6f68ac535efec1adb867ff"
    "abl_b firmware-update/abl.elf 155648 7c906fd151b4f12b54fa53a93ae7aef7afe1c8227e6f68ac535efec1adb867ff"
    "cmnlib64_a firmware-update/cmnlib64.img 496466 045ffc0d5768e0a37f7a11eb969bc7fce46b2cd7532ca5f829f596bdda1c86e2"
    "aop_a firmware-update/aop.img 184748 d5d1b9ca8f7e88fb417d3bad12479ffd5ffe5f1f2f26848f1c4542e6afbd5fcf"
    "devcfg_a firmware-update/devcfg.img 40336 4e1da51c74f8d099f95fb61b75bfa40ce283efae53e94d3f551dd724167995d0"
    "qupfw_a firmware-update/qupfw.img 65490 aa468db75354772bd478e10f1afa1b3254adc22de00f3b174e09843afaa13aea"
    "tz_a firmware-update/tz.img 2064384 b9d8d5afb6e926e625500613163aaa5424144e900f104941c44a305a1ed90261"
    "storsec_a firmware-update/storsec.img 20777 1c7e81836bbcce36431a5a8c80833e79f1a5d3e5a18d4c7703b099f9e8ca188d"
    "keymaster_a firmware-update/keymaster.img 232947 949584e4ddcbe0bdaff4540f6409a3c24e02443fe6751795cd34155ea6d532e6"
    "bluetooth firmware-update/bluetooth.img 765952 55f125335b601f08549584cf345823b732f92ba4bc23a56c7c69d62fa80fd798"
    "xbl_a firmware-update/xbl.img 3965832 74e2032b1f7706848eff0178ccc892b8ee363190642f8e78aad595823e46a179"
    "modem firmware-update/modem.img 172470272 70361079c61f2884687f9516744663156c184d6c2ddc83ee8c4887539429cd3c"
    "xbl_config_a firmware-update/xbl_config.img 98140 eaab4eee9cda564d5636b3746f8127dbe952de4aba68458fae76db23b5121654"
    "dsp firmware-update/dsp.img 33554432 26a1a424da36a3d97e43a53dee3e3819f3151849bfbe0b877b83716eaa874d36"
    "logo firmware-update/logo.img 22593536 5704fed21a077475c743b3135f5f4f9ba6f359386bfb404e741978f2e77f0ddc"
    "cmnlib_a firmware-update/cmnlib.img 377092 781bd9f1957803c59fd53e3e267ee05c4b5b14601e2a2a2a40463f45c628e678"
    "hyp_a firmware-update/hyp.img 396624 9d56e15cfb6f5be3bbcafea8cf06e3f901b432295df3be2c09f7797cb8e679fb"
)
