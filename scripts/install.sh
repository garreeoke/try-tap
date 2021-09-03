#!/bin/bash
#set -e

# TODO Setup args etc after it is working

######## Script starts here
KUBERNETES_CONTEXT=default
NAMESPACE=tap-install
OUT="./try-tap.log"
KAPP_VERSION="v0.39.0"
YTT_VERSION="v0.36.0"
IMGPKG_VERSION="v0.17.0"
KBLD_VERSION="v0.30.0"
KUBECTL_VERSION=v1.22.0
UAA_REFRESH_TOKEN="593092fe98754de894f37d4bea612bc4-r" # Make an option
TANZU_CLI_VERSION="v1.4.0-rc.5" # Make an option

### Load Helper Functions
. "${PROJECT_DIR}/scripts/functions.sh"

info "Running tap setup for Linux"

### Installing tools
install_kapp $KAPP_VERSION
install_ytt $YTT_VERSION
install_imgpkg $IMGPKG_VERSION
install_kbld $KBLD_VERSION
install_jq
install_kubectl $KUBECTL_VERSION
install_tanzu_cli $UAA_REFRESH_TOKEN

#detect_endpoint
#generate_passwords
#update_endpoint
#create_spin_endpoint

### Set up Kubernetes environment
info "Done for now ..."
exit 0
install_k3s

echo '' >>~/.bashrc
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# Install kapp controller
echo "Install kapp controller"
kapp deploy -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml

# Install app accelerator
info "Installing app accelerator ..."
# Install app live view
info "Installing app live view ..."
# Install harbor
info "Installing harbor ..."

# Install TBS
info "Installing Tanzu Build Service"