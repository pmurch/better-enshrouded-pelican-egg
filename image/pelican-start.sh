#!/bin/bash
# PID 1 chain step 2: Pelican's "$STARTUP" runner for the mbround18 image.
# Wings does not override the container command; it exports the egg's startup
# line as $STARTUP and expects the image to run it (pelican-eggs convention).
#
# DISPLAY / XDG_RUNTIME_DIR / Xvfb / SteamCMD bootstrap were arranged by
# pelican-init.sh before the base image's init hooks ran.
set -uo pipefail

if [ -z "${STARTUP:-}" ]; then
    echo "ERROR: STARTUP is not set — this image expects to run under Pelican Wings." >&2
    exit 1
fi

echo "[wrapper] pelican-start.sh running; STARTUP=${STARTUP}"

cd /home/container

# Defensive fallback: only fires if pelican-init.sh was bypassed entirely
# (e.g. `docker run --entrypoint ...`), since init normally sets DISPLAY.
if [ -z "${DISPLAY:-}" ]; then
    export DISPLAY=:0
    export SDL_VIDEODRIVER=x11
    Xvfb "${DISPLAY}" -screen 0 1024x768x16 >/dev/null 2>&1 &
    echo "$!" > /tmp/xvfb.pid
fi

# NOTE: no eval here! Wings already expands ${VAR} placeholders itself, and an
# `eval echo "$STARTUP"` would re-parse the whole `cmd && cmd && ...` chain and
# execute it inside this command substitution, swallowing every line it prints.
# The sed only converts the legacy {{VAR}} form for safety.
MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo ":/home/container$ ${MODIFIED_STARTUP}"

eval "${MODIFIED_STARTUP}" &
STARTED=$!

# Wings stops containers with SIGINT (egg stop: ^C). Give the game a chance to
# save via the CLI's own shutdown routine before the process group goes down.
trap 'enshrouded stop 2>/dev/null; kill "${STARTED}" 2>/dev/null' SIGINT SIGTERM
wait "${STARTED}"
