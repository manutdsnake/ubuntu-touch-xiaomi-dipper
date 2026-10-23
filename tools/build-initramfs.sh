#!/bin/bash
# Build ramdisk/halium-boot-ramdisk.img, the boot ramdisk deviceinfo points the
# build tools at (deviceinfo_prebuilt_boot_ramdisk): halium's released dynparts
# ramdisk plus initramfs-overlay/ (retrofit dynamic partitions, e2fsprogs 1.47).
# Commit the result; rerun whenever initramfs-overlay/ changes.
#
# The halium ramdisk is never unpacked and repacked: unpacking as a normal user
# loses ownership and special files. Instead our files go into a second cpio
# archive appended to the pristine one, and the kernel lets later entries win.
#
# DEV=1 also appends dev-overlay/initramfs (serial console on panic, boot
# checkpoints) - for the developer's phone only, never commit that build.
set -e
cd "$(dirname "$0")/.."
URL=https://github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64
PRISTINE=workdir/downloads/halium-boot-ramdisk-pristine.img
OUT=ramdisk/halium-boot-ramdisk.img
[ "${DEV:-0}" = 1 ] && OUT=workdir/halium-boot-ramdisk-dev.img

mkdir -p "$(dirname "$PRISTINE")" "$(dirname "$OUT")"
[ -s "$PRISTINE" ] || curl -fsSL -o "$PRISTINE" "$URL"

STAGE=$(mktemp -d)
LIST=$(mktemp)
CPIO=$(mktemp)
trap 'rm -rf "$STAGE" "$LIST" "$CPIO"' EXIT
cp -a initramfs-overlay/. "$STAGE"/
[ "${DEV:-0}" = 1 ] && cp -a dev-overlay/initramfs/. "$STAGE"/
( cd "$STAGE" && find . -mindepth 1 -printf '%P\n' | sort ) > "$LIST"
zcat "$PRISTINE" > "$CPIO"
( cd "$STAGE" && cpio -o -H newc -R 0:0 --quiet < "$LIST" ) >> "$CPIO"
gzip -9n < "$CPIO" > "$OUT"
echo "$OUT: $(stat -c%s "$OUT") bytes, pristine sha256 $(sha256sum "$PRISTINE" | cut -c1-16)"
