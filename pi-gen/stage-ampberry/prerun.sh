#!/bin/bash -e
# pi-gen stage boilerplate: start from the previous stage's rootfs.
if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi
