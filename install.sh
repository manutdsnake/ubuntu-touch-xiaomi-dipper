#!/usr/bin/env bash
# Ubuntu Touch installer for this port (device settings: installer/device.sh).
#
# Starting from any system on the phone (MIUI, LineageOS, another ROM or this
# port) with an unlocked bootloader, it:
#   1. downloads this port's release and checks it,
#   2. flashes the UBports recovery with fastboot (the only fastboot step),
#   3. in the recovery: checks the firmware and flashes it if needed (downloaded
#      from Xiaomi), writes the Android base Ubuntu Touch runs on (partition
#      table, vendor, odm, vbmeta), formats userdata and installs Ubuntu Touch.
#
# Usage: ./install.sh [--files DIR] [--skip-recovery] [--update]
#   --files DIR      keep downloaded files in DIR (default: ut-<codename>-files)
#   --skip-recovery  the phone is already in this release's UBports recovery
#   --update         newer release over an existing install of this port:
#                    keeps your data, skips firmware and Android base
#   --offline        use only the files already in DIR, download nothing
set -euo pipefail
SELF=$(readlink -f "$0")
HERE=$(dirname "$SELF")
# shellcheck source=installer/device.sh
. "$HERE/installer/device.sh"

OTA_FILES=(rootfs.tar.xz halium_halium_arm64.tar.xz "device_${CODENAME}.tar.xz" version.tar.xz)
KEYRINGS=(image-master.tar.xz image-signing.tar.xz)
BASE_URL="https://github.com/${REPO}/releases/latest/download"

FILES_DIR="ut-${CODENAME}-files"
SKIP_RECOVERY=0
UPDATE=0
OFFLINE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --files) FILES_DIR="$2"; shift ;;
        --skip-recovery) SKIP_RECOVERY=1 ;;
        --update|--keep-data) UPDATE=1 ;;
        --offline) OFFLINE=1 ;;
        -h|--help) sed -n '2,19p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
ask()  { local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]; }

if command -v sha256sum >/dev/null; then
    sha() { sha256sum "$1" | cut -c1-64; }
elif command -v shasum >/dev/null; then
    sha256sum() { shasum -a 256 "$@"; }
    sha() { shasum -a 256 "$1" | cut -c1-64; }
else
    die "sha256sum (or shasum) is not installed."
fi
for tool in adb fastboot unzip tar; do
    command -v "$tool" >/dev/null || die "'$tool' is not installed (see the README, 'What you need on the computer')."
done
if command -v curl >/dev/null; then
    fetch() { curl -fL --retry 3 -C - -o "$2" "$1"; }
elif command -v wget >/dev/null; then
    fetch() { wget -c -O "$2" "$1"; }
else
    die "Neither curl nor wget is installed."
fi

# adb shell forwards stdin and can lose its output when stdin is open; the
# installer never sends input to the phone.
adb() { command adb "$@" </dev/null; }

if [ -z "${ANDROID_SERIAL:-}" ]; then
    n=$(( $(adb devices | sed 1d | grep -c .) + $(fastboot devices 2>/dev/null | grep -c .) ))
    [ "$n" -le 1 ] || die "More than one phone is connected. Connect only the ${NAME}, or set ANDROID_SERIAL to its serial number."
fi

# Run a command on the phone and return its exit status (older adb clients
# do not pass it through).
rsh() {
    local t rc
    t=$(mktemp)
    adb shell "( $1 ); echo __rc=\$?" | tr -d '\r' | tee "$t" | grep -v '^__rc=' || true
    rc=$(tail -1 "$t"); rm -f "$t"
    [ "$rc" = "__rc=0" ]
}
# sha256 of <size> bytes of a block device on the phone, starting at block
# <offset> (4096-byte blocks, default 0)
dev_sha() {
    local dev=$1 size=$2 off=${3:-0}
    adb shell "dd if=$dev bs=4096 skip=$off count=$(( (size + 4095) / 4096 )) 2>/dev/null | head -c $size | sha256sum" \
        | tr -d '\r' | cut -c1-64
}
# Copy a local file onto a block device on the phone at block <offset> and
# verify it.
write_dev() {
    local file=$1 dev=$2 off=${3:-0} size sum
    size=$(wc -c < "$file" | tr -d ' ')
    sum=$(sha "$file")
    echo "  $(basename "$file") -> $dev${3:+ (at block $off)}"
    adb push "$file" /tmp/ut-write.img >/dev/null
    rsh "dd if=/tmp/ut-write.img of=$dev bs=4096 seek=$off conv=notrunc,fsync 2>/dev/null; r=\$?; rm -f /tmp/ut-write.img; exit \$r" \
        || die "Writing $dev failed."
    [ "$(dev_sha "$dev" "$size" "$off")" = "$sum" ] || die "$dev does not read back what was written."
}
wait_recovery() {
    echo "Waiting for the UBports recovery..."
    adb wait-for-recovery
    sleep 3
}

cat <<EOF

Ubuntu Touch installer for the ${NAME} (${CODENAME})

EOF
if [ "$UPDATE" = 0 ]; then
    cat <<EOF
This ERASES everything on the phone: the current system and all your data.
The phone needs:
  - an unlocked bootloader,
  - at least 50 % battery.
Anything else (MIUI, LineageOS, another ROM) is fine; the installer puts the
right firmware and Android base on the phone itself.
EOF
    ask "Back up what you want to keep first. Continue?" || exit 1
else
    echo "Update mode: the system is replaced, your data stays."
fi

# 1. Release files ----------------------------------------------------------
mkdir -p "$FILES_DIR"
cd "$FILES_DIR"
say "Downloading the release into $(pwd)"
need=(SHA256SUMS ubuntu_command "${RECOVERY_IMAGES[@]}" "${OTA_FILES[@]}")
for k in "${KEYRINGS[@]}"; do need+=("$k" "$k.asc"); done
if [ "$UPDATE" = 0 ]; then
    for e in "${BASE[@]}"; do need+=("${e%% *}"); done
fi
[ "$OFFLINE" = 1 ] || rm -f SHA256SUMS
for f in "${need[@]}"; do
    if [ ! -s "$f" ]; then
        [ "$OFFLINE" = 0 ] || die "$f is missing in $(pwd)."
        echo "Downloading $f"
        fetch "$BASE_URL/$f" "$f.part" && mv "$f.part" "$f"
    fi
done
say "Checking checksums"
for f in "${need[@]}"; do
    [ "$f" = SHA256SUMS ] && continue
    grep -E " [*]?$f\$" SHA256SUMS | sha256sum -c - \
        || die "$f is damaged or outdated. Delete it from $(pwd) and run the installer again."
done

# 2. UBports recovery --------------------------------------------------------
# A phone already in a recovery with a root adb shell (UBports, LineageOS,
# TWRP...) gets the UBports recovery written over adb: no fastboot needed.
if [ "$SKIP_RECOVERY" = 0 ] && [ "$(adb get-state 2>/dev/null)" = recovery ] \
        && [ "$(adb shell id -u 2>/dev/null | tr -d '\r')" = 0 ]; then
    if rsh 'grep -q allow-unsigned /system/bin/system-image-upgrader 2>/dev/null' >/dev/null \
            && [ "$(adb shell 'head -c '"$(wc -c < "${RECOVERY_IMAGES[0]}" | tr -d ' ')"' /dev/block/by-name/recovery | sha256sum' | cut -c1-64)" = "$(sha "${RECOVERY_IMAGES[0]}")" ]; then
        echo "The phone is already in this release's UBports recovery."
    else
        say "Writing the UBports recovery over adb"
        for img in "${RECOVERY_IMAGES[@]}"; do
            write_dev "$img" "/dev/block/by-name/${img%.img}"
        done
        adb reboot recovery
        sleep 5
    fi
    SKIP_RECOVERY=1
fi

if [ "$SKIP_RECOVERY" = 0 ]; then
    say "Flashing the UBports recovery"
    echo "Turn the phone off, then hold Volume Down + Power until the FASTBOOT screen"
    echo "appears, and connect it to this computer with a USB cable."
    if adb get-state >/dev/null 2>&1; then
        echo "(A phone is connected over adb - rebooting it into fastboot.)"
        adb reboot bootloader || true
    fi
    echo "Waiting for the phone in fastboot mode..."
    found=""
    for _ in $(seq 300); do
        if [ -n "$(fastboot devices 2>/dev/null)" ]; then found=1; break; fi
        sleep 1
    done
    [ -n "$found" ] || die "No phone in fastboot mode found. Check the cable and the USB port (README, 'If fastboot fails')."
    product=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p' | tr -d '\r') || true
    if [ -n "$product" ] && [ "$product" != "$CODENAME" ]; then
        die "This phone reports '$product', not '$CODENAME'. Wrong device or wrong installer."
    fi
    for img in "${RECOVERY_IMAGES[@]}"; do
        fastboot flash "${img%.img}" "$img" \
            || die "Flashing ${img%.img} failed. Unplug, re-enter fastboot (Volume Down + Power) and run the installer again (README, 'If fastboot fails')."
    done
    # Xiaomi's bootloader does not reliably honour "fastboot reboot recovery"
    # (the Mi 9 starts the normal system instead), so let the user do it.
    cat <<EOF

Now start the recovery: hold Volume Up + Power until the phone restarts and the
Ubuntu Touch recovery appears (about 10 seconds), then let go.
EOF
fi

wait_recovery
rsh 'test -x /system/bin/system-image-upgrader && grep -q allow-unsigned /system/bin/system-image-upgrader' >/dev/null \
    || die "The phone is not in the UBports recovery of this release. Flash recovery.img from $(pwd) and run again with --skip-recovery."
model=$(adb shell cat /proc/device-tree/model | tr -d '\r\0')
echo "$model" | grep -qi "$DT_MODEL_MATCH" || die "This phone is '$model', not a ${NAME}."

if [ "$UPDATE" = 0 ]; then
    # 3. Firmware -----------------------------------------------------------
    say "Checking the firmware ($FIRMWARE_NAME)"
    wrong=()
    for e in "${FIRMWARE[@]}"; do
        read -r part member size sum <<<"$e"
        if [ "$(dev_sha "/dev/block/by-name/$part" "$size")" != "$sum" ]; then
            wrong+=("$e")
            echo "  $part: different"
        fi
    done
    if [ ${#wrong[@]} = 0 ]; then
        echo "  The firmware is right."
    else
        echo "The phone needs the $FIRMWARE_NAME (${#wrong[@]} partitions differ)."
        echo "It is downloaded from Xiaomi's server (about $FIRMWARE_SIZE)."
        ask "Download and flash it now?" || die "The port does not work on other firmware."
        archive="firmware.$FIRMWARE_ARCHIVE"
        if [ ! -s "$archive" ] || [ "$(sha "$archive")" != "$FIRMWARE_SHA256" ]; then
            [ "$OFFLINE" = 0 ] || die "Put the firmware package ($FIRMWARE_URL) into $(pwd) as $archive."
            fetch "$FIRMWARE_URL" "$archive"
        fi
        [ "$(sha "$archive")" = "$FIRMWARE_SHA256" ] || die "The firmware download is damaged. Delete $(pwd)/$archive and try again."
        members=()
        while read -r m; do members+=("$m"); done < <(
            for e in "${wrong[@]}"; do read -r part member size sum <<<"$e"; echo "$member"; done | sort -u)
        echo "Unpacking the firmware..."
        rm -rf fw && mkdir -p fw
        case "$FIRMWARE_ARCHIVE" in
            zip) unzip -q -o "$archive" "${members[@]}" -d fw ;;
            tgz) tar -xzf "$archive" -C fw "${members[@]}" ;;
        esac || die "Unpacking the firmware package failed."
        for e in "${wrong[@]}"; do
            read -r part member size sum <<<"$e"
            [ "$(sha "fw/$member")" = "$sum" ] || die "Unexpected content of $member in the firmware package."
        done
        echo "Flashing the firmware - do not unplug the phone."
        for e in "${wrong[@]}"; do
            read -r part member size sum <<<"$e"
            write_dev "fw/$member" "/dev/block/by-name/$part"
        done
    fi

    # 4. Android base -------------------------------------------------------
    # The LP metadata comes first; vendor and odm go straight to where that
    # metadata places them on the physical partitions, so nothing needs mapping.
    say "Writing the Android base (partition table, vendor, odm, vbmeta)"
    for e in "${BASE[@]}"; do
        read -r f part off <<<"$e"
        write_dev "$f" "/dev/block/by-name/$part" "$off"
    done

    # 5. Userdata -----------------------------------------------------------
    say "Formatting userdata as ext4"
    adb shell 'umount /cache 2>/dev/null; umount /data 2>/dev/null; true'
    if adb shell 'grep -q " /data " /proc/mounts && echo busy' | grep -q busy; then
        die "The recovery is using /data. In the recovery menu choose 'Factory reset', then run: $SELF --skip-recovery --files $(pwd)"
    fi
    rsh 'mke2fs -F -t ext4 /dev/block/by-name/userdata >/dev/null' || die "Formatting userdata failed."
fi
rsh 'grep -q " /data " /proc/mounts || mount /dev/block/by-name/userdata /data' >/dev/null \
    || die "Cannot mount /data."
rsh 'mkdir -p /data/cache && (grep -q " /cache " /proc/mounts || mount -o bind /data/cache /cache) && mkdir -p /cache/recovery' >/dev/null \
    || die "Cannot prepare /cache."

# 6. Ubuntu Touch -------------------------------------------------------------
say "Copying Ubuntu Touch to the phone (about 1 GB)"
for f in "${OTA_FILES[@]}"; do
    adb push "$f" /cache/recovery/
    # Port releases are not signed by UBports: an empty signature file plus the
    # allow-unsigned marker below lets the upgrader take them.
    adb shell "touch /cache/recovery/$f.asc"
done
for k in "${KEYRINGS[@]}"; do
    adb push "$k" "$k.asc" /cache/recovery/
done
adb push ubuntu_command /cache/recovery/ubuntu_command
adb shell 'touch /cache/recovery/allow-unsigned'

say "Installing Ubuntu Touch"
# The recovery runs ubuntu_command by itself when it starts: it maps the
# dynamic partitions, installs, and boots into Ubuntu Touch.
adb reboot recovery
cat <<EOF
The phone now restarts into the recovery and installs Ubuntu Touch on its own
(about 5-10 minutes, a progress animation is shown). Do not unplug it. When it
is done it boots into Ubuntu Touch.
EOF
echo "The first boot takes a few minutes and may show the Mi logo for a while."
echo "Then set the phone up in the welcome wizard. Enjoy!"
