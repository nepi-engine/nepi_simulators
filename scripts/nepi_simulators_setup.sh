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

# NEPI simulators setup: prepares this computer (any Ubuntu with Docker;
# written for 26.04) to run the NEPI simulators in Docker. Nothing here
# installs a simulator: Gazebo and MuJoCo come in the simulator image, which
# nepi_simulators_pull fetches afterwards.
#
#   1. Numurus Software License acceptance
#   2. nepi_simulators_env_setup.sh: Docker and the tools around it
#   3. nepi_simulators_bash_setup.sh: the nepi_simulators_* commands
#
# Usage: bash nepi_simulators_setup.sh        (safe to re-run)

SCRIPT_FOLDER=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your own user, not root (it uses sudo where it needs to)."
    exit 1
fi

echo ""
echo "########################"
echo "NEPI SIMULATORS SETUP"
echo "########################"


####################################
# 1. License, nepi_setup's nepi_license_check.sh: the same terms and the same
# acceptance file as nepi_setup and the native simulator setups, so a
# computer that accepted there is not asked again. The check calls
# ask_yes_no from nepi_setup's bash utils, which this script does not load,
# so the same function is here.

function ask_yes_no {
    read -p "$1 ([y]es or [N]o): " choice
    case "$(echo "$choice" | tr '[:upper:]' '[:lower:]')" in
        y|yes) echo "yes" ;;
        *) echo "no" ;;
    esac
}

LICENSE_CHECK_FILE=${SCRIPT_FOLDER}/nepi_license_check.sh
source $LICENSE_CHECK_FILE
if [[ "$?" -ne 0 ]]; then
    exit 1
fi


####################################
# 2-3. Environment, then commands.

if ! bash "${SCRIPT_FOLDER}/nepi_simulators_env_setup.sh"; then
    echo "NEPI simulators environment setup failed -- fix the error above and re-run"
    exit 1
fi

if ! bash "${SCRIPT_FOLDER}/nepi_simulators_bash_setup.sh"; then
    echo "NEPI simulators bash setup failed -- fix the error above and re-run"
    exit 1
fi


####################################
# Next steps. A group added by the env setup is in the group database but not
# in this session's credentials: only a new login picks it up, so a new
# terminal window is not enough in that case.

if id -nG "$(id -un)" | grep -qw docker && ! id -Gn | grep -qw docker; then
    relogin_needed=1
else
    relogin_needed=0
fi

echo ""
echo "##################################"
echo "NEPI Simulators Setup Complete"
echo "##################################"
echo ""
if [[ $relogin_needed -eq 1 ]]; then
    echo "You were just added to the docker group. Log out and back in first,"
    echo "then open a terminal window."
else
    echo "Open a new terminal window, or in this one run:"
    echo "    source ~/.nepi_simulators_bash_utils"
fi
echo ""
echo "Then fetch the simulator image:"
echo "    nepi_simulators_pull"
echo ""
echo "and start a simulator:"
echo "    nepi_simulators_start gazebo     or     nepi_simulators_start mujoco"
echo "Stop it with nepi_simulators_stop."
echo ""
exit 0
