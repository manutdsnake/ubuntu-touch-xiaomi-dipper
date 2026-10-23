#!/usr/bin/env bash
# Ubuntu Touch installer for the Xiaomi Mi 8 (dipper).
#
# Downloads this port's release, checks it, flashes the UBports recovery, and
# installs Ubuntu Touch from the recovery the same way an OTA does. Read the
# README's "Before you start" first: the phone must already run LineageOS 22.2.
#
# Usage: ./install.sh [--files DIR] [--skip-recovery] [--keep-data]
#   --files DIR      use release files already downloaded into DIR
#   --skip-recovery  the UBports recovery from this release is already flashed;
#                    start with the phone booted into it
#   --keep-data      do not format userdata (only for re-installing over an
#                    existing Ubuntu Touch install of this port)
set -euo pipefail
SELF=$(readlink -f "$0")

CODENAME="dipper"
REPO="manutdsnake/ubuntu-touch-xiaomi-dipper"
RECOVERY_IMAGES=(recovery.img)
OTA_FILES=(rootfs.tar.xz halium_halium_arm64.tar.xz "device_${CODENAME}.tar.xz" version.tar.xz)
KEYRINGS=(image-master.tar.xz image-signing.tar.xz)
BASE_URL="https://github.com/${REPO}/releases/latest/download"

FILES_DIR=""
SKIP_RECOVERY=0
KEEP_DATA=0
while [ $# -gt 0 ]; do
    case "$1" in
        --files) FILES_DIR="$2"; shift ;;
        --skip-recovery) SKIP_RECOVERY=1 ;;
        --keep-data) KEEP_DATA=1 ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
ask()  { local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]; }
wait_enter() { read -r -p "$1 Press Enter to continue..." _; }

for tool in adb fastboot sha256sum; do
    command -v "$tool" >/dev/null || die "'$tool' is not installed (see the README, 'What you need on the computer')."
done
if command -v curl >/dev/null; then
    fetch() { curl -fL --retry 3 -o "$2" "$1"; }
elif command -v wget >/dev/null; then
    fetch() { wget -O "$2" "$1"; }
else
    die "Neither curl nor wget is installed."
fi

cat <<EOF

Ubuntu Touch installer for the Xiaomi Mi 8 (${CODENAME})

This ERASES Android and everything on the phone's internal storage.
Before you go on, the phone must:
  - have an unlocked bootloader,
  - run MIUI V12.5.2.0.QEACNXM firmware + LineageOS 22.2 (Android 15) for dipper, booted at least once,
  - be charged to at least 50 %.
Back up anything you want to keep first.
EOF
ask "Is all of the above true and do you want to continue?" || exit 1

# 1. Release files ----------------------------------------------------------
if [ -z "$FILES_DIR" ]; then
    FILES_DIR="ut-${CODENAME}-files"
fi
mkdir -p "$FILES_DIR"
cd "$FILES_DIR"
say "Release files in $(pwd)"
need=(SHA256SUMS ubuntu_command "${RECOVERY_IMAGES[@]}" "${OTA_FILES[@]}")
for k in "${KEYRINGS[@]}"; do need+=("$k" "$k.asc"); done
for f in "${need[@]}"; do
    if [ ! -s "$f" ] || [ "$f" = SHA256SUMS ]; then
        echo "Downloading $f"
        fetch "$BASE_URL/$f" "$f.part" && mv "$f.part" "$f"
    fi
done
say "Checking checksums"
sha256sum -c SHA256SUMS || die "A file is damaged. Delete it from $(pwd) and run the installer again."

# 2. UBports recovery --------------------------------------------------------
if [ "$SKIP_RECOVERY" = 0 ]; then
    say "Flashing the UBports recovery"
    echo "Turn the phone off, then hold Volume Down + Power until the FASTBOOT screen"
    echo "appears, and connect it to this computer with a USB cable."
    echo "(If the phone is running Android with USB debugging on, the installer can"
    echo " reboot it for you.)"
    if adb get-state >/dev/null 2>&1; then
        adb reboot bootloader || true
    fi
    echo "Waiting for the phone in fastboot mode..."
    product=""
    for _ in $(seq 120); do
        product=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p' | tr -d '\r') || true
        [ -n "$product" ] && break
        sleep 1
    done
    [ -n "$product" ] || die "No phone in fastboot mode found. Check the cable, or flash the recovery by hand (README, 'Manual installation') and run again with --skip-recovery."
    [ "$product" = "$CODENAME" ] || die "This phone reports '$product', not '$CODENAME'. Wrong device or wrong installer."
    for img in "${RECOVERY_IMAGES[@]}"; do
        part="${img%.img}"
        fastboot flash "$part" "$img" || die "Flashing $part failed. If fastboot hangs, unplug, re-enter fastboot (Volume Down + Power) and run the installer again."
    done
    echo "Booting into recovery..."
    if ! fastboot reboot recovery 2>/dev/null; then
        fastboot reboot || true
        echo "Your fastboot cannot reboot into recovery directly: as soon as the screen"
        echo "goes black, hold Volume Up + Power until the Ubuntu Touch recovery appears."
    fi
fi

say "Waiting for the UBports recovery"
echo "If the phone shows the Mi logo or boots Android instead, turn it off and hold"
echo "Volume Up + Power until the Ubuntu Touch recovery appears."
adb wait-for-recovery
sleep 3
adb shell 'test -x /system/bin/system-image-upgrader' \
    || die "The phone is in a recovery that is not the UBports recovery from this release."
adb shell 'grep -q allow-unsigned /system/bin/system-image-upgrader' \
    || die "This recovery is too old for the installer. Flash the recovery from this release."

# 3. Userdata ---------------------------------------------------------------
if [ "$KEEP_DATA" = 0 ]; then
    say "Formatting userdata as ext4 (Ubuntu Touch needs an unencrypted ext4 data partition)"
    ask "This erases ALL data on the phone. Continue?" || exit 1
    adb shell 'umount /cache 2>/dev/null; umount /data 2>/dev/null; true'
    if adb shell 'grep -q " /data " /proc/mounts && echo busy' | grep -q busy; then
        die "The recovery is using /data. In the recovery menu choose 'Factory reset' (it formats userdata as ext4), then run: $SELF --skip-recovery --keep-data --files $(pwd)"
    fi
    adb shell 'mke2fs -F -t ext4 /dev/block/by-name/userdata' || die "Formatting userdata failed."
fi
adb shell 'grep -q " /data " /proc/mounts || mount /dev/block/by-name/userdata /data' \
    || die "Cannot mount /data. Run the installer again without --keep-data."
adb shell 'mkdir -p /data/cache && (grep -q " /cache " /proc/mounts || mount -o bind /data/cache /cache) && mkdir -p /cache/recovery'

# 4. Copy the update ---------------------------------------------------------
say "Copying the system files to the phone (about 1 GB)"
for f in "${OTA_FILES[@]}"; do
    adb push "$f" /cache/recovery/
    # Port releases are not signed by UBports: an empty signature file plus the
    # allow-unsigned marker below lets the upgrader take them.
    adb shell "touch /cache/recovery/$f.asc"
done
for k in "${KEYRINGS[@]}"; do
    adb push "$k" "$k.asc" /cache/recovery/
done
adb shell 'touch /cache/recovery/allow-unsigned'
adb push ubuntu_command /cache/recovery/ubuntu_command

# 5. Install ----------------------------------------------------------------
say "Installing Ubuntu Touch (several minutes, do not unplug the phone)"
adb shell 'system-image-upgrader /cache/recovery/ubuntu_command' \
    || die "The installation failed; the log above says where. The phone stays in recovery, so you can run the installer again with --skip-recovery."

say "Done. Rebooting into Ubuntu Touch"
adb reboot
echo "The first boot takes a few minutes and may show the Mi logo for a while."
echo "Set the phone up in the welcome wizard. Enjoy!"
