# Ubuntu Touch for the Xiaomi Mi 8 (dipper)

Ubuntu Touch 24.04 (24.04-2.x) on Halium 16 for the Xiaomi Mi 8, running on
the vendor and odm partitions of LineageOS 22.2 (Android 15) and the MIUI V12.5.2.0.QEACNXM firmware. Community port, not an official UBports device yet.

> **Installing erases everything on the phone.** Back up your data first.

## What works

| Area | State |
|------|-------|
| Display, touch, brightness, rotation, notch-aware status bar | works |
| Calls (earpiece and speakerphone), call audio | works |
| Mobile data, VoLTE/IMS registration | works |
| Dual SIM | not tested |
| Wi-Fi, Bluetooth | works |
| Speaker, earpiece, microphone | works |
| Cameras: main, telephoto, selfie and IR (photo and video), torch | works |
| NFC | works |
| Vibration, notification LED | works |
| Waydroid (Android apps) | works |
| MTP and ADB over USB | works |
| Battery, charging, suspend (about 1.5 %/h idle with the screen off) | works |
| Fingerprint | works |
| GPS | works |
| Fast charging (wall charger) | works |
| Updates from System Settings | not available - see [Updating](#updating) |

Known issues:

- Switching camera lenses takes about 0.8 s (the camera HAL closes and reopens
  the device).

## What you need

- **A Xiaomi Mi 8, codename `dipper`.** Not the Mi 8 SE (sirius), Mi 8 Lite (platina), Mi 8 Pro (equuleus) or Mi 8 Explorer Edition (ursa).
- **An unlocked bootloader.** Unlock it with Xiaomi's official
  [Mi Unlock](https://en.miui.com/unlock/download_en.html) tool. It needs a Mi
  account bound to the phone (*Settings > Additional settings > Developer
  options > Mi Unlock status* in MIUI), Xiaomi usually makes you wait 7 days or
  more, and unlocking wipes the phone.
- **Nothing else on the phone.** It does not matter what runs on it now -
  MIUI, LineageOS, another ROM or Ubuntu Touch. The installer flashes the right
  firmware (MIUI V12.5.2.0.QEACNXM, downloaded from Xiaomi's server) and the Android base
  Ubuntu Touch needs by itself.
- **Battery at 50 % or more** and a USB cable that carries data.
- **A computer** with Windows, macOS or Linux, an internet connection and
  about 8 GB of free disk space (about 2 GB for this port, 2.2 GB for
  Xiaomi's firmware package, plus unpacking).

## Installation on Windows

1. Download [`install-windows.cmd`](https://github.com/manutdsnake/ubuntu-touch-xiaomi-dipper/releases/latest/download/install-windows.cmd).
2. Double-click it. If Windows says *Windows protected your PC*, click
   *More info* > *Run anyway* (it is a plain script; open it in Notepad to see
   what it does).
3. Follow the window. It downloads `adb` and `fastboot` (Google's
   platform-tools) and this port's release (about 2 GB), checks every file,
   and tells you when to press which buttons on the phone:
   - **Volume Down + Power** with the phone off, for the FASTBOOT screen
     (a phone running Android with USB debugging on is restarted into it
     automatically);
   - **Volume Up + Power** until the Ubuntu Touch recovery appears.

   Everything else is automatic: the installer checks the firmware and flashes
   it where needed (downloaded from Xiaomi), writes the Android base, formats
   the storage and copies Ubuntu Touch to the phone. The phone then installs
   it by itself (about 5-10 minutes, with a progress animation) and starts
   Ubuntu Touch. The first start takes a few minutes.

The downloads go to a folder `ut-dipper-files` next to `install-windows.cmd`;
delete it when the phone runs Ubuntu Touch. If something goes wrong the
installer says what to do and tries again; files already downloaded are kept.
If fastboot hangs while sending the recovery (see below) and the phone already
has a recovery (Ubuntu Touch, LineageOS, TWRP), start that recovery with
Volume Up + Power instead: the installer then writes its own recovery over adb
and fastboot is not needed at all.

Fastboot needs a USB driver. If Mi Unlock worked on this computer the driver
is already there; otherwise install the
[Google USB driver](https://developer.android.com/studio/run/win-usb) and, in
*Device Manager*, pick it for the phone while it shows FASTBOOT.

## Installation with the script (Linux, macOS)

The same steps from a terminal, with `adb` and `fastboot`
([platform-tools](https://developer.android.com/tools/releases/platform-tools),
Debian/Ubuntu: `sudo apt install adb fastboot`), `curl`, `unzip` and
`sha256sum` (macOS: `brew install coreutils`):

```sh
git clone https://github.com/manutdsnake/ubuntu-touch-xiaomi-dipper.git
cd ubuntu-touch-xiaomi-dipper
./install.sh
```

It downloads the [release](https://github.com/manutdsnake/ubuntu-touch-xiaomi-dipper/releases), checks every file, and tells you when to
press which buttons. If the phone is already in a recovery with a root adb
shell (UBports, LineageOS, TWRP), the script writes this port's recovery over
adb and fastboot is not needed at all. Options: `--files DIR` (where the
downloads go), `--offline` (use only files already in DIR), `--update`
(see below).

## If fastboot fails

Fastboot is used once, to flash `recovery.img`. If it hangs or the phone
drops out of the FASTBOOT screen ("press any key to shutdown"):

- use a USB port directly on the computer (no hub, no front panel) and try
  another port - on desktops the rear ports often sit on a different USB
  controller;
- a USB 2.0 hub between the phone and the computer often fixes hangs on
  USB 3 controllers (AMD ones in particular);
- after a failed attempt, restart the FASTBOOT screen (hold Volume Down +
  Power) before trying again;
- only one phone may be connected.

On some computers the Mi 8's fastboot answers commands but hangs as soon as an
image is sent. On an AMD Ryzen desktop it hung on several ports and worked on
another one, so try every port before giving up; otherwise use a USB 2.0 hub
or another computer for this one step.

## Updating

The port is not on the UBports update server yet, so *System Settings >
Updates* will not find new versions. To install a newer release **and keep
your data**, run `./install.sh --update` (it replaces the system only).
Running `install-windows.cmd` or `./install.sh` without `--update` erases
the phone.

## Going back to Android

Ubuntu Touch changes the dynamic partitions (`product` and `system_ext` are
gone, `system` is bigger), so restore them with a full install:

- **MIUI:** flash a dipper fastboot ROM with Xiaomi's MiFlash tool
  ("clean all"). This restores every partition, including the stock recovery.
- **LineageOS:** follow the LineageOS install guide for dipper from the start
  (it rewrites the dynamic partitions with `fastboot wipe-super`).

## Building from source

The port uses the standard UBports
[halium-generic-adaptation-build-tools](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools).
On Ubuntu 22.04 (or in an `ubuntu:22.04` container) with the usual kernel
build dependencies:

```sh
./build.sh -b workdir
```

This clones the kernel from
[manutdsnake/android_kernel_xiaomi_sdm845](https://github.com/manutdsnake/android_kernel_xiaomi_sdm845)
(branch `halium-16-dipper`: LineageOS lineage-22.2 plus this port's
commits), and writes `boot.img`, `recovery.img` and
`device_dipper.tar.xz` to `out/`. `.gitlab-ci.yml` runs the same build in
UBports' GSI port pipeline.

Repository layout:

| Path | What it is |
|------|------------|
| `deviceinfo` | device description for the build tools |
| `overlay/system/` | files that go into the root filesystem (services, configs, fixed libraries) |
| `ramdisk/halium-boot-ramdisk.img` | boot ramdisk: halium's initramfs plus `initramfs-overlay/` (built by `tools/build-initramfs.sh`) |
| `ramdisk-recovery-overlay/` | recovery changes: retrofit dynamic partitions, local installs |
| `patches/` | kernel patches (also on the kernel branch) and config fragments |
| `port-debs/` | rebuilt packages whose files are in `overlay/` |
| `install.sh`, `install-windows.cmd` | installers for Linux/macOS and Windows |
| `installer/` | installer settings (`device.sh`) and the Windows installer's PowerShell part (`tools/make-windows-installer.py` builds `install-windows.cmd` from both) |
| `tools/` | helper scripts (initramfs, mixer paths) |

### How the port differs from a usual Halium port

The Mi 8 has *retrofit* dynamic partitions: the Android "super" is spread over
the physical `system`, `vendor` and `cust` partitions, with the metadata in `system`.
Halium's initramfs and the UBports recovery only know a real `super`
partition, so this port carries:

- a `parse-android-dynparts` that reads retrofit metadata and maps partitions
  that span several block devices (in the boot ramdisk);
- a `system-image-upgrader` that uses `system` as the metadata device, so the
  root filesystem can live in the logical `system` partition.

These are meant to go upstream to UBports/Halium.

## Credits

UBports and Halium for Ubuntu Touch, the build tools and the GSI; LineageOS for
the kernel and the Android base the port runs on.
