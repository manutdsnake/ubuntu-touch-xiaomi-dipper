$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Host.UI.RawUI.WindowTitle = "Ubuntu Touch installer - $NAME"

$OTA_FILES = @('rootfs.tar.xz', 'halium_halium_arm64.tar.xz', "device_$CODENAME.tar.xz", 'version.tar.xz')
$KEYRINGS = @('image-master.tar.xz', 'image-signing.tar.xz')
$BASE_URL = "https://github.com/$REPO/releases/latest/download"

function Say($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan }
function Die($t) { Write-Host ''; Write-Host "ERROR: $t" -ForegroundColor Red; exit 1 }
function Step($t) {
    Write-Host ''
    Write-Host $t -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to continue (or close this window to stop)')
}

$curl = "$env:SystemRoot\System32\curl.exe"
$tar = "$env:SystemRoot\System32\tar.exe"
if (!(Test-Path $curl) -or !(Test-Path $tar)) { Die 'This installer needs Windows 10 (version 1803 or newer) or Windows 11.' }

function Fetch($url, $out) {
    & $curl -fL --retry 3 -o "$out.part" $url
    if ($LASTEXITCODE -ne 0) { Remove-Item -Force -ErrorAction SilentlyContinue "$out.part"; Die "Downloading $url failed. Check the internet connection and start the installer again." }
    Move-Item -Force "$out.part" $out
}
function Sha($f) { (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLower() }

$files = Join-Path (Split-Path -Parent $env:UT_SELF) "ut-$CODENAME-files"
New-Item -ItemType Directory -Force $files | Out-Null
Set-Location -LiteralPath $files

Write-Host ''
Write-Host "Ubuntu Touch installer for the $NAME ($CODENAME)" -ForegroundColor White
Write-Host ''
Write-Host 'This ERASES everything on the phone: the current system and all your data.'
Write-Host 'The phone needs an unlocked bootloader and at least 50 % battery.'
Write-Host 'Anything else (MIUI, LineageOS, another ROM) is fine: the installer puts the'
Write-Host 'right firmware and Android base on the phone itself.'
Write-Host ''
Write-Host "Files are downloaded to $files"
Write-Host 'Do not connect any other Android phone while the installer runs.'
Step 'Back up what you want to keep first.'

# 1. Tools and release files --------------------------------------------------
$pt = Join-Path $files 'platform-tools'
$adb = Join-Path $pt 'adb.exe'
$fastboot = Join-Path $pt 'fastboot.exe'
if (!(Test-Path $adb) -or !(Test-Path $fastboot)) {
    Say 'Downloading adb and fastboot (Android platform-tools from Google)'
    Fetch 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' 'platform-tools.zip'
    Expand-Archive -Force -LiteralPath 'platform-tools.zip' -DestinationPath $files
    Remove-Item -Force 'platform-tools.zip'
    if (!(Test-Path $adb)) { Die 'Unpacking platform-tools failed.' }
}

Say 'Downloading the release'
$need = @('ubuntu_command') + $RECOVERY_IMAGES + $OTA_FILES
foreach ($k in $KEYRINGS) { $need += $k; $need += "$k.asc" }
foreach ($e in $BASE) { $need += ($e -split '\s+')[0] }
Remove-Item -Force -ErrorAction SilentlyContinue 'SHA256SUMS'
Fetch "$BASE_URL/SHA256SUMS" 'SHA256SUMS'
$sums = @{}
foreach ($l in Get-Content 'SHA256SUMS') {
    if ($l -match '^([0-9a-f]{64})\s+\*?(\S+)\s*$') { $sums[$matches[2]] = $matches[1] }
}
foreach ($f in $need) {
    if (!$sums.ContainsKey($f)) { Die "$f is not listed in the release's SHA256SUMS." }
    if ((Test-Path $f) -and ((Sha $f) -eq $sums[$f])) { continue }
    Write-Host "Downloading $f"
    Fetch "$BASE_URL/$f" $f
    if ((Sha $f) -ne $sums[$f]) { Remove-Item -Force $f; Die "$f is damaged. Start the installer again to download it once more." }
}
Write-Host 'All files are complete.'

# Phone helpers ---------------------------------------------------------------
# Commands for the phone must not contain double quotes: Windows PowerShell
# drops them when it passes arguments to adb.
function Rsh($cmd) {
    $out = @(& $adb shell "( $cmd ); echo __rc=`$?" | ForEach-Object { "$_".TrimEnd("`r") })
    $out | Where-Object { $_ -notmatch '^__rc=' } | ForEach-Object { Write-Host $_ }
    return (($out | Select-Object -Last 1) -eq '__rc=0')
}
function DevSha($dev, $size, $off = 0) {
    $count = [int64][math]::Ceiling([double]$size / 4096)
    $r = "$(& $adb shell "dd if=$dev bs=4096 skip=$off count=$count 2>/dev/null | head -c $size | sha256sum")".Trim()
    if ($r.Length -ge 64) { return $r.Substring(0, 64) }
    return ''
}
function WriteDev($file, $dev, $off = 0) {
    $size = (Get-Item -LiteralPath $file).Length
    $sum = Sha $file
    Write-Host "  $(Split-Path -Leaf $file) -> $dev"
    & $adb push $file /tmp/ut-write.img | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Copying $file to the phone failed." }
    if (!(Rsh "dd if=/tmp/ut-write.img of=$dev bs=4096 seek=$off conv=notrunc,fsync 2>/dev/null; r=`$?; rm -f /tmp/ut-write.img; exit `$r")) { Die "Writing $dev failed." }
    if ((DevSha $dev $size $off) -ne $sum) { Die "$dev does not read back what was written." }
}
function State { "$(& $adb get-state 2>$null)".Trim() }

& $adb start-server 2>$null | Out-Null
$n = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }).Count + @(& $fastboot devices 2>$null | Where-Object { $_ -match '\S' }).Count
if ($n -gt 1) { Die "More than one phone is connected. Connect only the $NAME." }

# 2. UBports recovery ---------------------------------------------------------
# A phone already in this release's recovery (for example when the installer
# is started again after a problem) skips fastboot.
$inRecovery = $false
if ((State) -eq 'recovery') {
    $rsize = (Get-Item $RECOVERY_IMAGES[0]).Length
    $inRecovery = (Rsh 'grep -q allow-unsigned /system/bin/system-image-upgrader') -and ((DevSha '/dev/block/by-name/recovery' $rsize) -eq (Sha $RECOVERY_IMAGES[0]))
    if ($inRecovery) { Write-Host 'The phone is already in the Ubuntu Touch recovery.' }
}

if (!$inRecovery) {
    Say 'Flashing the Ubuntu Touch recovery'
    if ((State) -match '^(device|recovery)$') {
        Write-Host 'A phone is connected over adb - restarting it into fastboot.'
        & $adb reboot bootloader 2>$null | Out-Null
    } elseif (!(& $fastboot devices 2>$null)) {
        Write-Host 'Turn the phone off. Then hold Volume Down + Power until the FASTBOOT screen'
        Write-Host 'appears, and connect the phone to this computer with a USB cable.'
    }
    Write-Host 'Waiting for the phone in fastboot mode...'
    $found = $false
    for ($i = 0; $i -lt 300; $i++) {
        if (& $fastboot devices 2>$null) { $found = $true; break }
        Start-Sleep -Seconds 1
    }
    if (!$found) { Die "No phone in fastboot mode found. Try another USB cable or port, and see 'If fastboot fails' in the README (the USB driver)." }
    $product = ''
    foreach ($l in (& $fastboot getvar product 2>&1 | ForEach-Object { "$_" })) {
        if ($l -match '^product:\s*(\S+)') { $product = $matches[1] }
    }
    if ($product -and $product -ne $CODENAME) { Die "This phone reports '$product', not '$CODENAME'. Wrong phone or wrong installer." }
    foreach ($img in $RECOVERY_IMAGES) {
        & $fastboot flash ([IO.Path]::GetFileNameWithoutExtension($img)) $img
        if ($LASTEXITCODE -ne 0) { Die "Flashing $img failed. Unplug the phone, enter fastboot again (Volume Down + Power) and start the installer again." }
    }
    Write-Host ''
    Write-Host 'Now start the recovery: hold Volume Up + Power until the phone restarts and' -ForegroundColor Yellow
    Write-Host 'the Ubuntu Touch recovery appears (about 10 seconds), then let go.' -ForegroundColor Yellow
}

Write-Host 'Waiting for the Ubuntu Touch recovery...'
& $adb wait-for-recovery
Start-Sleep -Seconds 3
if (!(Rsh 'test -x /system/bin/system-image-upgrader && grep -q allow-unsigned /system/bin/system-image-upgrader')) {
    Die 'The phone is not in the Ubuntu Touch recovery of this release. Start the installer again.'
}
$model = "$(& $adb shell cat /proc/device-tree/model)" -replace "[`0`r`n]", ''
if ($model -notmatch $DT_MODEL_MATCH) { Die "This phone is '$model', not a $NAME." }

# 3. Firmware -----------------------------------------------------------------
Say "Checking the firmware ($FIRMWARE_NAME)"
$wrong = @()
foreach ($e in $FIRMWARE) {
    $p = $e -split '\s+'
    if ((DevSha "/dev/block/by-name/$($p[0])" $p[2]) -ne $p[3]) { $wrong += , $p; Write-Host "  $($p[0]): different" }
}
if ($wrong.Count -eq 0) {
    Write-Host '  The firmware is right.'
} else {
    Write-Host "The phone needs the $FIRMWARE_NAME ($($wrong.Count) partitions differ)."
    Write-Host "It is downloaded from Xiaomi's server (about $FIRMWARE_SIZE)."
    $archive = "firmware.$FIRMWARE_ARCHIVE"
    if (!(Test-Path $archive) -or ((Sha $archive) -ne $FIRMWARE_SHA256)) { Fetch $FIRMWARE_URL $archive }
    if ((Sha $archive) -ne $FIRMWARE_SHA256) { Remove-Item -Force $archive; Die 'The firmware download is damaged. Start the installer again.' }
    $members = @($wrong | ForEach-Object { $_[1] } | Sort-Object -Unique)
    Write-Host 'Unpacking the firmware...'
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue fw
    New-Item -ItemType Directory fw | Out-Null
    & $tar -xf $archive -C fw @members
    if ($LASTEXITCODE -ne 0) { Die 'Unpacking the firmware package failed.' }
    foreach ($p in $wrong) {
        if ((Sha "fw/$($p[1])") -ne $p[3]) { Die "Unexpected content of $($p[1]) in the firmware package." }
    }
    Write-Host 'Flashing the firmware - do not unplug the phone.'
    foreach ($p in $wrong) { WriteDev "fw/$($p[1])" "/dev/block/by-name/$($p[0])" }
    Remove-Item -Recurse -Force fw
}

# 4. Android base -------------------------------------------------------------
Say 'Writing the Android base (partition table, vendor, odm, vbmeta)'
foreach ($e in $BASE) {
    $p = $e -split '\s+'
    WriteDev $p[0] "/dev/block/by-name/$($p[1])" $p[2]
}

# 5. Userdata -----------------------------------------------------------------
Say 'Formatting userdata as ext4'
& $adb shell 'umount /cache 2>/dev/null; umount /data 2>/dev/null; true' | Out-Null
if ("$(& $adb shell "grep -q ' /data ' /proc/mounts && echo busy")" -match 'busy') {
    Die "The recovery is using /data. In the recovery menu choose 'Factory reset', then start the installer again."
}
if (!(Rsh 'mke2fs -F -t ext4 /dev/block/by-name/userdata >/dev/null')) { Die 'Formatting userdata failed.' }
if (!(Rsh "grep -q ' /data ' /proc/mounts || mount /dev/block/by-name/userdata /data")) { Die 'Cannot mount /data.' }
if (!(Rsh "mkdir -p /data/cache && (grep -q ' /cache ' /proc/mounts || mount -o bind /data/cache /cache) && mkdir -p /cache/recovery")) { Die 'Cannot prepare /cache.' }

# 6. Ubuntu Touch -------------------------------------------------------------
Say 'Copying Ubuntu Touch to the phone (about 1 GB)'
foreach ($f in $OTA_FILES) {
    & $adb push $f /cache/recovery/
    if ($LASTEXITCODE -ne 0) { Die "Copying $f to the phone failed." }
    # Port releases are not signed by UBports: an empty signature file plus the
    # allow-unsigned marker below lets the upgrader take them.
    & $adb shell "touch /cache/recovery/$f.asc" | Out-Null
}
foreach ($k in $KEYRINGS) {
    & $adb push $k "$k.asc" /cache/recovery/
    if ($LASTEXITCODE -ne 0) { Die "Copying $k to the phone failed." }
}
& $adb push ubuntu_command /cache/recovery/ubuntu_command
if ($LASTEXITCODE -ne 0) { Die 'Copying ubuntu_command to the phone failed.' }
& $adb shell 'touch /cache/recovery/allow-unsigned' | Out-Null

Say 'Installing Ubuntu Touch'
# The recovery runs ubuntu_command by itself when it starts: it maps the
# dynamic partitions, installs, and boots into Ubuntu Touch.
& $adb reboot recovery
Write-Host 'The phone now restarts into the recovery and installs Ubuntu Touch on its own'
Write-Host '(about 5-10 minutes, a progress animation is shown). Do not unplug it. When it'
Write-Host 'is done it boots into Ubuntu Touch.'
Write-Host 'The first boot takes a few minutes and may show the Mi logo for a while.'
Write-Host 'Then set the phone up in the welcome wizard. Enjoy!'
Write-Host ''
Write-Host "You can delete the folder $files afterwards."
