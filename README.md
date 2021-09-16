# Tanzu Application Platform All-in-One Beta Quickstart

Try-tap is a simple way to install beta components TAP inside a single VM. This is a completely unsecure
setup, and is meant just to install TAP components and try them out.

## Background

Try-tap performs the following actions when run on a single linux instance

- Installs k3s with Traefik
- Installs needed command line tools for TAP
- Installs tap components
  - Application Accelerator for VMware Tanzu
  - Application Live View for VMware Tanzu
  - Cloud Native Runtimes
  - Tanzu Build Service  
- Installs local, **unsecure**, harbor registry on k3s

Each branch of this repo should be a working install for a beta version

## Requirements

To use try-tap, make sure your Linux instance meets the following requirements
- Linux distribution running in a VM or bare metal
    - Ubuntu 18.04 or Debian 10 (some tool install may not work on Debian)
    - 4 vCPUs (8 recommended)
    - 16GiB of RAM (32 if you can get it)
    - 20 GiB of HDD
    - Install curl, git, and tar (if not already installed)
        `sudo apt-get install curl git tar`

## Installation

1. Clone the try-tap repo for the needed branch
    `git clone https://github.com/garreeoke/try-tap.git -b beta1`
2. Go to try-tap directory
3. Export following variables
    `export TANZU_NET_USER="[YOUR USER]"`
    `export TANZU_NET_PASSWORD="[YOUR PASSWORD]"`
    `export TANZU_NET_REFRESH_TOKEN="[YOUR REFRESH TOKEN]"`
        - This can be generated/found in your profile on Tanzu Network. This is the value from UAA API TOKEN
4. Execute the install script, be sure to use sudo and -E to use the exported variables
   `sudo -E scripts/install.sh`
5. Once the script completes, try access the URLs shown at the end of the script
6. If you are on public cloud you may have to find your public ip address and open ports (80, 443, 5112, 6443,8080, 8081)
    - HTTP: 80, 5112, 8080, 8081
    - HTTPS: 443, 6443
7. Follow the guided tutorial

## Uninstall K3s
`sudo scripts/uninstall-k3s.sh`