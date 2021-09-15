#!/bin/bash

echo "Cleaning up try-tap"
# REMOVE K3S
/usr/local/bin/k3s-uninstall.sh
# Remove tmp bundle
rm -rf /tmp/bundle


