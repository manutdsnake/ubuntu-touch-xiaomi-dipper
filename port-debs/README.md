# Packages rebuilt for the port

Copied from the Mi 9 port (`~/xiaomi-cepheus/port-debs`, see its README for how
they were built). Their files are unpacked into `overlay/system/` (without
usr/share/doc); dpkg state is not touched - the device tarball can only add or
replace files, so the archive versions stay registered as installed.

| Package | Why |
|---|---|
| biometryd-bin, libbiometry2, qml-module-biometryd 0.4.0 (upstream main `15ddc2c`) | The archive build dlopens `libbiometry_fp_api.so`, which the Halium 16 container does not have; main talks to the AIDL fingerprint HAL (`IFingerprint/default`, LineageOS' fingerprint-service.xiaomi) through libgbinder. The Mi 9's UDFPS patch only writes /run/biometryd/udfps-active and is harmless here. |
