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

# NEPI simulators bash setup: puts the nepi_simulators_* commands in your
# shell. Called by nepi_simulators_setup.sh; safe to run on its own and to
# re-run (for example after a git pull of this repo, to refresh the commands).
#
#   1. ~/.nepi_simulators_config: the device address and share user, asked
#      for once (kept on re-runs)
#   2. ~/.nepi_simulators_bash_utils: a copy of resources/bash/
#      nepi_simulators_bash_utils, with this checkout's resources folder
#      pinned at the end so the commands find the scripts in
#      resources/docker from any shell
#   3. .bashrc: sources that copy in every new shell (marker-guarded)
#
# It also retires the earlier nepi_sim prototype (~/.nepi_sim_utils and its
# .bashrc block), carrying its settings over.

SCRIPT_FOLDER=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
RESOURCES_FOLDER=$(dirname "$SCRIPT_FOLDER")/resources

UTILS_SOURCE=${RESOURCES_FOLDER}/bash/nepi_simulators_bash_utils
UTILS_DEST=${HOME}/.nepi_simulators_bash_utils
CONFIG_FILE=${HOME}/.nepi_simulators_config
BASHRC=${HOME}/.bashrc
BASHRC_MARKER="##### Source NEPI Simulators Bash Utils #####"

OLD_UTILS=${HOME}/.nepi_sim_utils
OLD_CONFIG=${HOME}/.nepi_sim_config
OLD_BASHRC_MARKER="##### Source NEPI Sim Utils #####"

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your own user, not root."
    exit 1
fi

echo ""
echo "########################"
echo "NEPI SIMULATORS BASH SETUP"
echo "########################"
echo ""

[[ -f "$BASHRC" ]] || cp /etc/skel/.bashrc "$BASHRC"


####################################
# 1. Settings. Defaults, in order: the nepi_sim prototype's settings, an
# existing NEPI remote setup (NEPI_IP/NEPI_USER from nepi_setup's bash utils),
# the factory values.

if [[ -f "$CONFIG_FILE" ]]; then
    echo "Keeping existing ${CONFIG_FILE}"
else
    image=numurusinc/nepi:nepi-sim-latest
    share=/mnt/nepi_share_storage
    gpu=auto
    default_ip=${NEPI_IP:-192.168.179.103}
    default_user=${NEPI_USER:-nepi}
    if [[ -f "$OLD_CONFIG" ]]; then
        old_values=$(
            source "$OLD_CONFIG"
            echo "${NEPI_IP}|${NEPI_USER}|${NEPI_SIM_IMAGE}|${NEPI_SIM_SHARE}|${NEPI_SIM_GPU}"
        )
        IFS='|' read -r old_ip old_user old_image old_share old_gpu <<< "$old_values"
        default_ip=${old_ip:-$default_ip}
        default_user=${old_user:-$default_user}
        image=${old_image:-$image}
        share=${old_share:-$share}
        gpu=${old_gpu:-$gpu}
        echo "Carrying settings over from ${OLD_CONFIG}"
    fi

    read -r -p "NEPI device address [${default_ip}]: " nepi_ip
    read -r -p "NEPI storage share user [${default_user}]: " nepi_user

    cat > "$CONFIG_FILE" <<EOF
# NEPI simulators settings, read by the nepi_simulators_* commands every time
# they run, so edits apply to the next command without opening a new terminal.

# The NEPI device the simulators connect to, and its nepi_storage share user.
NEPI_IP=${nepi_ip:-$default_ip}
NEPI_USER=${nepi_user:-$default_user}

# The simulator image. Point this at a locally built image to test one.
NEPI_SIMULATORS_IMAGE=${image}

# Where this computer mounts the device's nepi_storage share.
NEPI_SIMULATORS_SHARE=${share}

# GPU route into the container: auto, nvidia, dri or none.
NEPI_SIMULATORS_GPU=${gpu}
EOF
    echo "Wrote ${CONFIG_FILE}"
fi


####################################
# 2. The commands: an installed copy, with this checkout's resources folder
# pinned. NEPI_SIMULATORS_RESOURCES_FOLDER, computed inside the file, would
# resolve to $HOME once the copy is what .bashrc sources.

cp "$UTILS_SOURCE" "$UTILS_DEST"
echo "export NEPI_SIMULATORS_RESOURCES_FOLDER='${RESOURCES_FOLDER}'" >> "$UTILS_DEST"
chmod 664 "$UTILS_DEST"
echo "Installed ${UTILS_DEST}"


####################################
# 3. .bashrc.

if grep -qxF "$BASHRC_MARKER" "$BASHRC"; then
    echo "${BASHRC} already sources it"
else
    # Single quotes intended: .bashrc expands these when it runs.
    # shellcheck disable=SC2016
    {
        echo ' '
        echo "$BASHRC_MARKER"
        echo "NEPI_SIMULATORS_BASH_UTILS_FILE=${UTILS_DEST}"
        echo 'if [ -f ${NEPI_SIMULATORS_BASH_UTILS_FILE} ]; then'
        echo '    . ${NEPI_SIMULATORS_BASH_UTILS_FILE}'
        echo 'fi'
    } >> "$BASHRC"
    echo "Added the NEPI simulators commands to ${BASHRC}"
fi


####################################
# 4. Retire the nepi_sim prototype: its block in .bashrc (the marker line and
# the four lines it wrote after it), its utils copy, and its config, kept as
# a .bak.

if grep -qxF "$OLD_BASHRC_MARKER" "$BASHRC"; then
    cp "$BASHRC" "${BASHRC}.nepi_simulators.bak"
    sed -i "/^${OLD_BASHRC_MARKER}\$/,+4d" "$BASHRC"
    echo "Removed the nepi_sim prototype commands from ${BASHRC} (backup: ${BASHRC}.nepi_simulators.bak)"
fi
if [[ -f "$OLD_UTILS" ]]; then
    rm -f "$OLD_UTILS"
    echo "Removed ${OLD_UTILS}"
fi
if [[ -f "$OLD_CONFIG" ]]; then
    mv -f "$OLD_CONFIG" "${OLD_CONFIG}.bak"
    echo "Moved ${OLD_CONFIG} to ${OLD_CONFIG}.bak"
fi

echo ""
echo "NEPI simulators commands installed"
exit 0
