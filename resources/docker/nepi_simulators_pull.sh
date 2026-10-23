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
## Redistributions in source code must retain this top-level comment block.
## Plagiarizing this software to sidestep the license obligations is illegal.
##
## Contact Information:
## ====================
## - mailto:nepi@numurus.com
##

# Pull the NEPI simulator image (NEPI_SIMULATORS_IMAGE in
# ~/.nepi_simulators_config, numurusinc/nepi_simulations:latest by default).
#
# Usage: nepi_simulators_pull
#
# Run it after setup and whenever you want the latest simulators. A running
# simulator keeps the image it started with; restart it to use the new one.

SCRIPT_FOLDER=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
source "$(dirname "$SCRIPT_FOLDER")/bash/nepi_simulators_bash_utils"

nepi_simulators_load_config
nepi_simulators_preflight || exit 1

echo "Pulling ${NEPI_SIMULATORS_IMAGE}"
if ! docker pull "$NEPI_SIMULATORS_IMAGE"; then
    echo "Pull failed. Check the internet connection, and that ${NEPI_SIMULATORS_IMAGE}"
    echo "is the image you mean: NEPI_SIMULATORS_IMAGE in ${NEPI_SIMULATORS_CONFIG_FILE}"
    echo "(point it at a locally built image to use that instead)."
    exit 1
fi

if running=$(nepi_simulators_running); then
    echo "The running ${running} simulator still uses the previous image."
    echo "Restart it to use this one: nepi_simulators_stop, then nepi_simulators_start ${running}"
fi
