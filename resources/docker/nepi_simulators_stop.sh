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

# Stop whichever NEPI simulator is running.
#
# Usage: nepi_simulators_stop
#
# The container's entrypoint has the simulator service stop everything it
# started (simulation, SITL, ROS), which can take up to 30 s, so docker stop
# gets 45 s before it would kill the container. The stopped container is
# kept, so nepi_simulators_logs can still show its log, until the next start
# replaces it.

SCRIPT_FOLDER=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
source "$(dirname "$SCRIPT_FOLDER")/bash/nepi_simulators_bash_utils"

nepi_simulators_load_config
command -v docker >/dev/null 2>&1 || { echo "No simulator is running"; exit 0; }

if ! running=$(nepi_simulators_running); then
    echo "No simulator is running"
    exit 0
fi

echo "Stopping the ${running} simulator and everything it started"
if docker stop -t 45 "$NEPI_SIMULATORS_CONTAINER" >/dev/null; then
    echo "The ${running} simulator stopped"
    exit 0
fi
echo "docker stop failed -- check: docker ps -a --filter name=${NEPI_SIMULATORS_CONTAINER}"
exit 1
