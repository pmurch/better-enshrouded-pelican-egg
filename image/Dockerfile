# ───────────────────────────────────────────────────────────
# Pelican-compatible wrapper around mbround18/enshrouded-docker
#
# Wings (Pelican daemon) boots game containers with:
#   * a read-only root filesystem
#   * the server volume bind-mounted at /home/container
#   * no Cmd override — the *image* is expected to run $STARTUP
#   * container env vars that override the image's baked-in ENV
#
# The upstream image handles everything else (steamcmd install, config
# generation from env vars, Proton launch, graceful stop). This wrapper only
# relocates the runtime-writable paths onto the mounted volume and provides a
# Pelican entrypoint.
# ───────────────────────────────────────────────────────────
ARG BASE_IMAGE=mbround18/enshrouded-docker
ARG BASE_TAG=proton-latest
FROM ${BASE_IMAGE}:${BASE_TAG}

USER root

# The enshrouded CLI hard-codes its game directory to /home/steam/enshrouded.
# Replace it with a symlink to Pelican's writable volume (created at build
# time, so it survives the read-only rootfs; it resolves at runtime).
RUN mkdir -p /home/container \
    && rm -rf /home/steam/enshrouded \
    && ln -s /home/container /home/steam/enshrouded \
    && chown steam:steam /home/container

# Point every writable runtime location at the mounted volume. HOME matters
# most: steamcmd, the Proton/Steam SDK symlinks, and Proton logs all follow it.
# PROTON_PATH is deliberately the *directory* here; the base image's init hook
# appends /proton and persists the real file path at container start.
ENV HOME=/home/container \
    USER=steam \
    LD_LIBRARY_PATH=/home/container/.steam/sdk32:/home/container/.steam/sdk64:/home/steam/.steam/sdk32:/home/steam/.steam/sdk64 \
    STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/container/.steam/steam \
    STEAM_COMPAT_DATA_PATH=/home/container/.proton \
    WINEPREFIX=/home/container/.proton/pfx \
    PROTON_PATH=/home/steam/.steam/root/compatibilitytools.d/current \
    LAUNCH_MODE=proton

WORKDIR /home/container

COPY --chmod=0755 pelican-init.sh /usr/local/bin/pelican-init.sh
COPY --chmod=0755 pelican-start.sh /usr/local/bin/pelican-start.sh

# The base image's ENTRYPOINT runs the steamcmd-bases Proton/Xvfb init hooks
# and then `exec "$@"`, so we keep it in the chain and pass our start script
# as the command it will exec.
ENTRYPOINT ["/usr/local/bin/pelican-init.sh"]
CMD ["/usr/local/bin/pelican-start.sh"]
