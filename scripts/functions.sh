#!/bin/bash

function log() {
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  ORANGE='\033[0;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
  LEVEL=$1
  MSG=$2
  case $LEVEL in
  "INFO") HEADER_COLOR=$GREEN MSG_COLOR=$NS ;;
  "WARN") HEADER_COLOR=$ORANGE MSG_COLOR=$NS ;;
  "KUBE") HEADER_COLOR=$ORANGE MSG_COLOR=$CYAN ;;
  "ERROR") HEADER_COLOR=$RED MSG_COLOR=$NS ;;
  esac
  printf "${HEADER_COLOR}[%-5.5s]${NC} ${MSG_COLOR}%b${NC}" "${LEVEL}" "${MSG}"
  printf "$(date +"%D %T") [%-5.5s] %b" "${LEVEL}" "${MSG}" >>"$OUT"
}

function info() {
  log "INFO" "$1\n"
}

function warn() {
  log "WARN" "$1\n"
}

function error() {
  log "ERROR" "$1\n" && exit 1
}

function handle_generic_kubectl_error() {
  error "Error executing command:\n$ERR_OUTPUT"
}

function exec_kubectl_mutating() {
  log "KUBE" "$1\n"
  ERR_OUTPUT=$({ $1 >>"$OUT"; } 2>&1)
  EXIT_CODE=$?
  [[ $EXIT_CODE != 0 ]] && $2
}

install_k3s () {
  info "--- Installing K3s ---"
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san $(cat ${BASE_DIR}/secrets/public_ip)" INSTALL_K3S_VERSION="v1.19.7+k3s1" K3S_KUBECONFIG_MODE="644" sh -
  #curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.19.7+k3s1" K3S_KUBECONFIG_MODE=644 sh -
  info " --- END K3s --- "
}

## Install carvel tools
install_kapp () {
  # $1 is the release string: v0.39.0
  info "Installing kapp $1"
  wget https://github.com/vmware-tanzu/carvel-kapp/releases/download/$1/kapp-linux-amd64
  chmod +x ./kapp-linux-amd64
  mv ./kapp-linux/amd64 /usr/local/bin
  # Execute kapp command
  # TODO error checking
  kapp -v
}

install_ytt () {
  info "Installing ytt $1"
  wget https://github.com/vmware-tanzu/carvel-ytt/releases/download/$1/ytt-linux-amd64
  chmod +x ./ytt-linux-amd64
  mv ./ytt-linux-amd64 /usr/local/bin/ytt
  ytt --version
}

install_imgpkg () {
  info "Installing imgpkg $1"
  wget https://github.com/vmware-tanzu/carvel-imgpkg/releases/download/$1/imgpkg-linux-amd64
  chmod +x ./imgpkg-linux-amd64
  mv ./imgpkg-linux-amd64 /usr/local/bin/imgpkg
  imgpgk -v
}

install_kbld () {
  info "Installing kbld $1"
  #$1 is the release string: v0.30.0
  wget https://github.com/vmware-tanzu/carvel-kbld/releases/download/$1/kbld-linux-amd64
  chmod +x ./kbld-linux-amd64
  mv ./kbld-linux-amd64 /usr/local/bin/kbld
  kbld --version
}

install_kubectl () {
  info "Installing kubectl $1"
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x ./kubectl
  mv ./kubectl /usr/local/bin/kubectl
}

install_tanzu_cli () {
  info "Installing tanzu cli"
  # Get access token
  ACCESS_TOKEN=$(curl -X POST https://network.pivotal.io/api/v2/authentication/access_tokens -d '{"refresh_token":$1}' | jq '.access_token')
  wget -O tanzu-cli-bundle-linux-amd64.tar --header="Authorization: Bearer $ACCESS_TOKEN" https://network.pivotal.io/api/v2/products/tanzu-application-platform/releases/941562/product_files/1030933/download
  install cli/core/$2/tanzu-core-linux_amd64 /usr/local/bin/tanzu
  tanzu version
  tanzu plugin clean
  tanzu plugin install -v $2 --local cli package
  tanzu package version
}

install_yq () {
  info "Installing yq"
  sudo curl -sfL https://github.com/mikefarah/yq/releases/download/v4.7.1/yq_linux_amd64 -o /usr/local/bin/yq
  sudo chmod +x /usr/local/bin/yq
  if [[ ! -e "/usr/local/bin/yq" ]]; then
    error "failed to install yq - please manually install https://github.com/mikefarah/yq/"
    exit 1
  fi
}

install_jq () {
info "Installing jq"

# install prereqs jq
# if jq is not installed
if ! jq --help > /dev/null 2>&1; then
  # only try installing if a Debian system
  if apt-get -v > /dev/null 2>&1; then 
    info "Using apt-get to install jq"
    sudo apt-get update && sudo apt-get install -y jq
  else
    error "ERROR: Unsupported OS! Cannot automatically install jq. Please try install jq first before rerunning this script"
    exit 2
  fi
fi
}

detect_endpoint () {
  info "Trying to detect endpoint"
  if [[ ! -s ${BASE_DIR}/secrets/public_ip || -n "$1" ]]; then
    if [[ -n "${PUBLIC_IP}" ]]; then
      info "Using provided public IP ${PUBLIC_IP}"
      echo "${PUBLIC_IP}" > ${BASE_DIR}/secrets/public_ip
    else 
      if [[ $(curl -m 1 169.254.169.254 -sSfL &>/dev/null; echo $?) -eq 0 ]]; then
        # change to ask AWS public metadata? http://169.254.169.254/latest/meta-data/public_ipv4
        #rm ${BASE_DIR}/secrets/public_ip
        #while [[ ! -s ${BASE_DIR}/secrets/public_ip ]]; do
        info "Detected cloud metadata endpoint"
        info "Trying to determine public IP address (using 'curl -m http://169.254.169.254/latest/meta-data/public-ipv4')"
        info "IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 | tee ${BASE_DIR}/secrets/public_ip)"
        #  info "Trying to determine public IP address (using 'dig +short TXT o-o.myaddr.l.google.com @ns1.google.com')"
        #  dig +short TXT o-o.myaddr.l.google.com @ns1.google.com | sed 's|"||g' | tee ${BASE_DIR}/secrets/public_ip
        #done
      else
        info "No cloud metadata endpoint detected, detecting interface IP (and storing in ${BASE_DIR}/secrets/public_ip): $(ip r get 8.8.8.8 | awk 'NR==1{print $7}' | tee ${BASE_DIR}/secrets/public_ip)"
      fi
    fi
  else
    info "Using existing Public IP from ${BASE_DIR}/secrets/public_ip"
    cat ${BASE_DIR}/secrets/public_ip
  fi
}

update_endpoint () {
  #PUBLIC_ENDPOINT="spinnaker.$(cat "${BASE_DIR}/secrets/public_ip").nip.io"   # use nip.io which is a DNS that will always resolve.
  PUBLIC_ENDPOINT="$(cat "${BASE_DIR}/secrets/public_ip")" 

  info "Updating spinsvc templates with new endpoint: ${PUBLIC_ENDPOINT}"
  #yq eval -i '.spec.rules[0].host = "'${PUBLIC_ENDPOINT}'"' ${BASE_DIR}/expose/ingress-traefik.yml 
  yq eval -i 'del(.spec.rules[0].host)' ${BASE_DIR}/expose/ingress-traefik.yml 
  yq eval -i '.spec.spinnakerConfig.config.security.uiSecurity.overrideBaseUrl = "'https://${PUBLIC_ENDPOINT}'"' ${BASE_DIR}/expose/patch-urls.yml
  yq eval -i '.spec.spinnakerConfig.config.security.apiSecurity.overrideBaseUrl = "'https://${PUBLIC_ENDPOINT}/api'"' ${BASE_DIR}/expose/patch-urls.yml
  yq eval -i '.spec.spinnakerConfig.config.security.apiSecurity.corsAccessPattern = "'https://${PUBLIC_ENDPOINT}'"' ${BASE_DIR}/expose/patch-urls.yml
}

generate_passwords () {
  # for PASSWORD_ITEM in spinnaker_password minio_password mysql_password; do
  for PASSWORD_ITEM in spinnaker_password; do
    if [[ ! -s ${BASE_DIR}/secrets/${PASSWORD_ITEM} ]]; then
      info "Generating password [${BASE_DIR}/secrets/${PASSWORD_ITEM}]:"
      openssl rand -base64 36 | tee ${BASE_DIR}/secrets/${PASSWORD_ITEM}
    else
      warn "Password already exists: [${BASE_DIR}/secrets/${PASSWORD_ITEM}]"
    fi
  done
  
  SPINNAKER_PASSWORD=$(cat "${BASE_DIR}/secrets/spinnaker_password")
}

create_spin_endpoint () {

info "Creating spin_endpoint helper function"

sudo tee /usr/local/bin/spin_endpoint <<-'EOF'
#!/bin/bash
#echo "$(kubectl get spinsvc spinnaker -n spinnaker -ojsonpath='{.spec.spinnakerConfig.config.security.uiSecurity.overrideBaseUrl}')"
echo "$(yq e '.spec.spinnakerConfig.config.security.uiSecurity.overrideBaseUrl' BASE_DIR/expose/patch-urls.yml)"
[[ -f BASE_DIR/secrets/spinnaker_password ]] && echo "username: 'admin'"
[[ -f BASE_DIR/secrets/spinnaker_password ]] && echo "password: '$(cat BASE_DIR/secrets/spinnaker_password)'"
EOF
sudo chmod 755 /usr/local/bin/spin_endpoint

sudo sed -i "s|BASE_DIR|${BASE_DIR}|g" /usr/local/bin/spin_endpoint
}

restart_k3s (){
  info "Restarting k3s"
  /usr/local/bin/k3s-killall.sh
  sudo systemctl restart k3s
}
