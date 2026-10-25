#!/bin/bash
# PID 1 chain step 2: Pelican's "$STARTUP" runner for the mbround18 image.
# Wings does not override the container command; it exports the egg's startup
# line as $STARTUP and expects the image to run it (pelican-eggs convention).
set -uo pipefail

cd /home/container

# Proton/DXVK need an X display even headless. The base image's
# 20-proton-init.sh normally starts Xvfb and exports DISPLAY, but under the
# panel's read-only rootfs that hook can bail early, so provide a fallback.
if [ -z "${DISPLAY:-}" ]; then
    export DISPLAY=:0
    export SDL_VIDEODRIVER=x11
    Xvfb "${DISPLAY}" -screen 0 1024x768x16 >/dev/null 2>&1 &
    echo "$!" > /tmp/xvfb.pid
fi

MODIFIED_STARTUP=$(eval echo "$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")
echo ":/home/container$ ${MODIFIED_STARTUP}"

eval "${MODIFIED_STARTUP}" &
STARTED=$!

# Wings stops containers with SIGINT (egg stop: ^C). Give the game a chance to
# save via the CLI's own shutdown routine before the process group goes down.
trap 'enshrouded stop 2>/dev/null; kill "${STARTED}" 2>/dev/null' SIGINT SIGTERM
wait "${STARTED}"
