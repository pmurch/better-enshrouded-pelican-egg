#!/bin/bash
# PID 1 chain step 1: runs BEFORE the base image's scripts.d init hooks and
# execs the base entrypoint, so every variable exported here is inherited by
# the hooks, the server, and the Proton processes it spawns.
#
# Wings runs containers unprivileged (uid 999 "container" by default) with a
# read-only rootfs and no display — none of what the steamcmd-bases hooks
# assume is set up for them. Pre-arrange it here.
set -uo pipefail

# Wine/Proton want a valid XDG runtime directory; the panel provides none.
export XDG_RUNTIME_DIR=/tmp/xdg
mkdir -p "${XDG_RUNTIME_DIR}" && chmod 700 "${XDG_RUNTIME_DIR}"

# The base image's Proton detection follows $HOME, but Proton itself is baked
# into the image at /home/steam/.steam/root (read-only, and nothing needs to
# write there at runtime — steamcmd lives under ~/.local/share, the prefix
# under ~/.proton). Link it into the relocated HOME so 20-proton-init.sh can
# find and initialize Proton instead of exiting 1.
mkdir -p "${HOME}/.steam"
[ -e "${HOME}/.steam/root" ] || ln -s /home/steam/.steam/root "${HOME}/.steam/root"

# A display must exist BEFORE the init hooks touch Wine/Proton (wineboot
# fails without one), so Xvfb starts here rather than in pelican-start.sh.
# The base image's 20-proton-init.sh defers to an already-set DISPLAY.
if ! xdpyinfo "${DISPLAY:-:0}" >/dev/null 2>&1; then
    export DISPLAY=:0
    export SDL_VIDEODRIVER=x11
    echo "🖥️ Starting virtual display on ${DISPLAY}..."
    Xvfb "${DISPLAY}" -screen 0 1024x768x16 >/dev/null 2>&1 &
    echo "$!" > /tmp/xvfb.pid
    sleep 1
fi

# SteamCMD self-update bootstrap. The enshrouded CLI performs this silently
# inside `enshrouded setup` (captured output), which looks exactly like a hang
# on first boot. Do it here instead: progress is visible in the panel console
# and a stalled bootstrap times out loudly. Once ~/.local/share/Steam is
# populated (persisted on the server volume), this is skipped entirely.
if [ -f "${HOME}/.local/share/Steam/steamcmd/linux64/steamclient.so" ]; then
    echo "✅ SteamCMD already bootstrapped (cached on server volume)"
else
    echo "⬇️ Bootstrapping SteamCMD (first boot only, may take a few minutes)..."
    timeout "${STEAMCMD_BOOTSTRAP_TIMEOUT:-900}" steamcmd +quit || echo "⚠️ SteamCMD bootstrap did not complete cleanly (exit $?) — the server will retry it during install."
    echo "✅ SteamCMD bootstrap finished"
fi

exec /opt/steamcmd-bases/entrypoint.sh "$@"
