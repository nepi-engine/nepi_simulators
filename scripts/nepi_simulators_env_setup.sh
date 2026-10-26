#!/bin/bash

##
## Copyright (c) 2024 Numurus <https://www.numurus.com>.
##
## This file is part of nepi setup tools (nepi_setup) repo
## (see https://github.com/nepi-engine/nepi_setup)
##
## License: nepi setup tools are licensed under the "Numurus Software License", 
## which can be found at: <https://numurus.com/wp-content/uploads/Numurus-Software-License-Terms.pdf>
##
## Redistributions in source code must retain this top-level comment block, 
## Along with any License Check related code and checks.
## Plagiarizing this software to sidestep the license obligations is illegal.
##
## Contact Information:
## ====================
## - mailto:nepi@numurus.com
##

# NEPI simulators environment setup: installs Docker if it is not already
# installed, following nepi_setup's docker_env_setup.sh, plus the few things
# the nepi_simulators commands need around it (the share-mount and display
# tools, and the docker group). Called by nepi_simulators_setup.sh; safe to
# run on its own and to re-run. Exits non-zero if Docker is not installed at
# the end.
#
# This runs as its own process (bash, not source), and without nepi_setup's
# bash utils, so NEPI_ARCH and is_valid_rpi -- which docker_env_setup.sh gets
# from those -- are set up here.

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your own user, not root (it uses sudo where it needs to)."
    exit 1
fi


####################################
# License check, nepi_setup's nepi_license_check.sh. When this is called by
# nepi_simulators_setup.sh the license is already accepted and this passes;
# run on its own, it asks. The check calls ask_yes_no from nepi_setup's bash
# utils, which this script does not load, so the same function is here.

function ask_yes_no {
    read -p "$1 ([y]es or [N]o): " choice
    case "$(echo "$choice" | tr '[:upper:]' '[:lower:]')" in
        y|yes) echo "yes" ;;
        *) echo "no" ;;
    esac
}

SCRIPT_FOLDER=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
LICENSE_CHECK_FILE=${SCRIPT_FOLDER}/nepi_license_check.sh
source $LICENSE_CHECK_FILE
if [[ "$?" -ne 0 ]]; then
    exit 1
fi
sudo -v || exit 1


####################################
# Architecture, as nepi_setup's is_valid_* checks detect it.

function is_valid_rpi(){
    grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null
}

case "$(uname -m)" in
    x86_64)        NEPI_ARCH=amd64 ;;
    aarch64|arm64) NEPI_ARCH=arm64 ;;
    *)             NEPI_ARCH=unknown ;;
esac

sudo apt-get update
sudo apt-get install --fix-broken -y

echo ""
echo "NEPI ARCHITECTURE: ${NEPI_ARCH}"
echo ""

echo "Checking for Docker software"
if command -v docker &>/dev/null; then
    echo "Docker Installed"
else

    if [[ "$NEPI_ARCH" == 'amd64' ]]; then
        echo ""
        echo "######################################"
        echo "Installing Docker"
        echo "######################################"
        echo ""

        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
        "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        \"$(. /etc/os-release && echo \"$VERSION_CODENAME\")\" stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else 
        arch_val=$(uname -m)
        echo "Arch ${arch_val} not supported yet"
    fi

fi

sudo apt-get update
sudo apt-get install --fix-broken -y

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is not installed -- see the messages above"
    exit 1
fi

echo ""
echo "Starting Docker Service"
sudo systemctl daemon-reload
sudo systemctl start docker.socket
sudo systemctl start docker

####################################
# What the nepi_simulators commands need besides Docker: mount.cifs to mount
# the device's nepi_storage share, xauth to give the container the display.

sudo apt-get install -y cifs-utils xauth

####################################
# docker group, so the nepi_simulators commands run docker without sudo.
# Group changes only reach new login sessions, so nepi_simulators_setup.sh
# tells you to log out and back in when this adds you.

if id -nG "$(id -un)" | grep -qw docker; then
    echo "docker group: $(id -un) is a member"
else
    echo "Adding $(id -un) to the docker group"
    sudo usermod -aG docker "$(id -un)" || exit 1
fi

####################################
# GPU. Only reported: NVIDIA machines need the NVIDIA Container Toolkit for
# the simulators to use the GPU (see docker_env_setup.sh's toolkit section).

if lspci 2>/dev/null | grep -qi nvidia; then
    if sudo docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
        echo "GPU: NVIDIA, through the NVIDIA Container Toolkit"
    else
        echo "WARNING: this computer has an NVIDIA GPU, but Docker has no nvidia runtime, so"
        echo "WARNING: the simulators will use software rendering. Install the NVIDIA Container"
        echo "WARNING: Toolkit, then run: sudo nvidia-ctk runtime configure --runtime=docker"
    fi
elif [[ -d /dev/dri ]]; then
    echo "GPU: /dev/dri (Intel/AMD) -- passed into the container"
fi

echo ""
echo "Docker: $(docker --version 2>/dev/null)"
echo "NEPI simulators environment ready"
exit 0
