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
TANZU_NET_USER="taaron@vmware.com"
TANZU_NET_PASS="GwRnBa0#"

### Load Helper Functions
. ./scripts/functions.sh

info "Running tap setup for Linux"

### Installing tools
install_kapp $KAPP_VERSION
install_ytt $YTT_VERSION
install_imgpkg $IMGPKG_VERSION
install_kbld $KBLD_VERSION
install_jq
install_kubectl $KUBECTL_VERSION
install_tanzu_cli "$UAA_REFRESH_TOKEN" "$TANZU_CLI_VERSION"

#detect_endpoint
#generate_passwords
#update_endpoint
#create_spin_endpoint

### Set up Kubernetes environment
info "Done for now ..."
install_k3s
# Install kapp controller
echo "Install kapp controller"
kapp deploy -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml
# Setup package repo
kubectl create namespace tap-install
kubectl create secret docker-registry tap-registry -n tap-install --docker-server='registry.pivotal.io' --docker-username=$TANZU_NET_USER --docker-password=$TANZU_NET_PASS
kapp deploy -a tap-package-repo -n tap-install -f ./manifests/tap-package-repo.yaml -y
tanzu package repository list -n tap-install

echo "EXITING"
rm -rf cli
exit 0

echo '' >>~/.bashrc
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# Install app accelerator
info "Installing app accelerator ..."
# Install app live view
info "Installing app live view ..."
# Install harbor
info "Installing harbor ..."

# Install TBS
info "Installing Tanzu Build Service"