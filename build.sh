#!/bin/bash
set -xe
umask 022

# The device tarball keeps the checkout's file modes; a umask 002 checkout
# would make /etc, /usr/... group-writable on the phone.
chmod -R go-w overlay

[ -d build ] || git clone https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools -b main build
./build/build.sh "$@"
