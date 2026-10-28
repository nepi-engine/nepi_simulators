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

# Start one NEPI simulator in its container.
#
# Usage: nepi_simulators_start gazebo|mujoco [share password]
#
# Stops the other simulator first if it is running, pulls the image if it is
# not here yet, mounts the device's nepi_storage share, and starts the
# container with the share, the display, the GPU and NEPI_IP/NEPI_USER passed
# in. Then waits for the simulator service inside to report in. Safe to
# re-run: if the same simulator is already running, it says so and stops.

SCRIPT_FOLDER=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
source "$(dirname "$SCRIPT_FOLDER")/bash/nepi_simulators_bash_utils"

SIM=$1
PASSWORD=$2

case "$SIM" in
    gazebo|mujoco) ;;
    *)
        echo "Usage: nepi_simulators_start gazebo|mujoco [share password]"
        exit 2
        ;;
esac

nepi_simulators_load_config
nepi_simulators_preflight || exit 1


####################################
# 1. One simulator at a time.

if running=$(nepi_simulators_running); then
    if [[ "$running" == "$SIM" ]]; then
        echo "The ${SIM} simulator is already running (nepi_simulators_logs to follow it)"
        exit 0
    fi
    echo "Stopping the running ${running} simulator first: one simulator runs at a time"
    bash "${SCRIPT_FOLDER}/nepi_simulators_stop.sh" || exit 1
fi


####################################
# 2. The image: pulled on first use.

if ! docker image inspect "$NEPI_SIMULATORS_IMAGE" >/dev/null 2>&1; then
    echo "The simulator image ${NEPI_SIMULATORS_IMAGE} is not on this computer yet"
    bash "${SCRIPT_FOLDER}/nepi_simulators_pull.sh" || exit 1
fi


####################################
# 3. NEPI storage.

nepi_simulators_mount "$PASSWORD" || exit 1


####################################
# 4. Container arguments.

# A stopped container from the last run is kept until now so its log can
# still be read with nepi_simulators_logs.
docker rm -f "$NEPI_SIMULATORS_CONTAINER" >/dev/null 2>&1

# Host networking: the container reaches the device the same way this computer
# does, and every connection is outbound from the simulator side, so nothing
# is published. --init forwards docker stop's SIGTERM to the entrypoint and
# reaps the many processes the services start and stop.
#
# The share is bound in as it is mounted now. If it is unmounted and mounted
# again on this computer while the container runs, the container keeps the
# old, dead mount, so restart the simulator after remounting. A share that
# drops and reconnects on its own (device reboot) is the same mount and needs
# nothing.
run_args=(
    -d --name "$NEPI_SIMULATORS_CONTAINER"
    --label "nepi.simulator=${SIM}"
    --init
    --network host
    -e "NEPI_IP=${NEPI_IP}"
    -e "NEPI_USER=${NEPI_USER}"
    --mount "type=bind,source=${NEPI_SIMULATORS_SHARE},target=/mnt/nepi_share_storage"
    --group-add "$(id -g)"
)

# Display. On Ubuntu 26.04 the desktop is Wayland-only; X11 apps such as
# gzclient and the MuJoCo viewer go through XWayland, which is what DISPLAY
# points at. The container gets its own copy of the X cookie, rewritten
# (ffff family) to match any hostname, kept in XDG_RUNTIME_DIR, which only
# you can read on this computer.
if [[ -z "$DISPLAY" ]]; then
    if [[ -n "$WAYLAND_DISPLAY" ]]; then
        echo "Display: Wayland with no XWayland (DISPLAY unset) -- the simulator windows cannot open"
    else
        echo "Display: none -- running headless"
    fi
else
    run_args+=(-e "DISPLAY=${DISPLAY}" -v /tmp/.X11-unix:/tmp/.X11-unix:ro)
    if command -v xauth >/dev/null 2>&1; then
        xauth_file=${XDG_RUNTIME_DIR:-/tmp}/nepi_simulators.xauth
        rm -f "$xauth_file"
        touch "$xauth_file"
        xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' | xauth -f "$xauth_file" nmerge - 2>/dev/null
        chmod 0644 "$xauth_file"
        run_args+=(-e XAUTHORITY=/tmp/.nepi_simulators.xauth -v "${xauth_file}:/tmp/.nepi_simulators.xauth:ro")
        echo "Display: ${DISPLAY}"
    else
        echo "Display: ${DISPLAY}, WITHOUT an X cookie (xauth not installed: sudo apt install xauth)"
    fi
fi

# GPU. NEPI_SIMULATORS_GPU in the config overrides the choice:
#   nvidia  the NVIDIA Container Toolkit injects the host driver's GL/EGL
#           libraries, so the 20.04 container uses this computer's driver
#   dri     /dev/dri for Intel and AMD, rendered by the container's Mesa
#           (20.04's, which may not know very new GPUs -- the container
#           warns if that falls back to software rendering)
gpu_mode=$NEPI_SIMULATORS_GPU
if [[ "$gpu_mode" == "auto" ]]; then
    if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
        gpu_mode=nvidia
    elif [[ -d /dev/dri ]]; then
        gpu_mode=dri
    else
        gpu_mode=none
    fi
fi
case "$gpu_mode" in
    nvidia)
        run_args+=(--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all)
        ;;
    dri)
        run_args+=(--device /dev/dri)
        for gid in $(stat -c '%g' /dev/dri/* 2>/dev/null | sort -u); do
            run_args+=(--group-add "$gid")
        done
        ;;
    none)
        ;;
    *)
        echo "Unknown NEPI_SIMULATORS_GPU '${gpu_mode}' (use auto, nvidia, dri or none) -- using none"
        gpu_mode=none
        ;;
esac
echo "GPU: ${gpu_mode}"


####################################
# 5. Start, and wait for the service inside to report in. Gazebo's start
# launches Gazebo and ROS first, so allow it a while.

echo "Starting the ${SIM} simulator container from ${NEPI_SIMULATORS_IMAGE}"
if ! docker run "${run_args[@]}" "$NEPI_SIMULATORS_IMAGE" "$SIM" >/dev/null; then
    echo "docker run failed"
    exit 1
fi

# The --group-add GIDs above have no names in the container, so a login shell
# there (simslogin) warns "groups: cannot find name for group ID". Name the
# unnamed ones after this computer's groups, prefixed host_.
group_args=()
for gid in $(docker inspect -f '{{join .HostConfig.GroupAdd " "}}' "$NEPI_SIMULATORS_CONTAINER"); do
    name=$(getent group "$gid" | cut -d: -f1)
    group_args+=("${gid}:host_${name:-$gid}")
done
docker exec -u root "$NEPI_SIMULATORS_CONTAINER" sh -c \
    'for g; do getent group "${g%%:*}" >/dev/null || groupadd -g "${g%%:*}" "${g#*:}"; done' \
    sh "${group_args[@]}" >/dev/null 2>&1

waited=0
while [[ $waited -lt 120 ]]; do
    if [[ "$(docker inspect -f '{{.State.Running}}' "$NEPI_SIMULATORS_CONTAINER" 2>/dev/null)" != "true" ]]; then
        echo ""
        echo "The ${SIM} simulator container stopped during startup:"
        docker logs --tail 40 "$NEPI_SIMULATORS_CONTAINER" 2>&1
        exit 1
    fi
    if docker logs "$NEPI_SIMULATORS_CONTAINER" 2>&1 | grep -q "service started with PID"; then
        docker logs "$NEPI_SIMULATORS_CONTAINER" 2>&1 | grep -E "WARNING|OpenGL renderer|service started"
        echo ""
        echo "The ${SIM} simulator is running. Select it in the device's Sim Connector and Deploy."
        echo "Follow its log: nepi_simulators_logs    Stop it: nepi_simulators_stop"
        exit 0
    fi
    sleep 1
    waited=$((waited + 1))
done
echo "The ${SIM} service has not reported in after ${waited} s -- check nepi_simulators_logs"
exit 1
