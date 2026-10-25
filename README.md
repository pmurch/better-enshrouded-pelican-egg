# Enshrouded Pelican Egg (mbround18 edition)

Runs the [mbround18/enshrouded-docker](https://github.com/mbround18/enshrouded-docker)
server inside a [Pelican](https://pelican.dev) panel with as little custom code
as possible: the game install, config generation, Proton launch and graceful
shutdown all stay inside the upstream image.

```
enshrouded-pelican-egg/
├── egg-enshrouded-mbround18.json   # the egg to import into the panel
└── image/                          # thin Pelican wrapper around the upstream image
    ├── Dockerfile
    ├── pelican-init.sh
    └── pelican-start.sh
```

## Why a wrapper image is needed

Wings (the Pelican daemon) differs from plain `docker run` in three ways that
matter for this image (verified against the wings source):

1. **The startup command is passed as the `STARTUP` env var** — Wings never
   overrides the container's `Cmd`. The image's own entrypoint is expected to
   run it (the pelican-eggs convention).
2. **The root filesystem is read-only.** Everything the server writes (steamcmd
   data, the Proton prefix, SDK symlinks) must live under the mounted volume at
   `/home/container` or in the `/tmp` tmpfs.
3. The container runs as the Wings-configured UID (root by default), which
   pairs fine with the above.

The wrapper (`image/`) is layered on `mbround18/enshrouded-docker:proton-latest`
and does exactly three things:

- symlinks `/home/steam/enshrouded` (the game directory, hard-coded in the
  upstream CLI) to `/home/container`, so the install and saves land in the
  panel-visible server files;
- re-points `HOME`, `WINEPREFIX`, `STEAM_COMPAT_DATA_PATH`,
  `STEAM_COMPAT_CLIENT_INSTALL_PATH`, `LD_LIBRARY_PATH` at `/home/container`,
  and fixes `PROTON_PATH` so the base image's Proton/Xvfb init hooks work
  unchanged;
- adds a Pelican entrypoint that executes `$STARTUP` and, on stop, calls
  `enshrouded stop` so the world gets a chance to save.

## Setting up

1. **Build the image.** Either:
   - push this repo to GitHub — the included Action publishes
     `ghcr.io/<your-org>/enshrouded-pelican:latest`; or
   - build it on the Wings host:
     `docker build -t enshrouded-pelican image/`
     (an egg may reference local images with a `~` prefix, e.g.
     `~enshrouded-pelican:latest`, which skips registry pulling).
2. **Edit the egg JSON**: replace `ghcr.io/YOURORG/...` in `docker_images`
   with your image reference (and `author` if you like).
3. **Import the egg** in the panel (Nests → Import).
4. **Create a server** with **2 allocations**, both TCP+UDP: `15636` (game)
   and `15637` (query). If your allocation ports differ, set the *Game Port*
   and *Query Port* egg variables to match — Wings forwards the container port
   with the same number as the allocation.

First boot downloads the dedicated server through SteamCMD (several GB) and
builds the Proton prefix; be patient — the console shows install progress, and
the server is up when `[Session] 'HostOnline' (up)!` appears.

## Configuration

The egg exposes the common knobs (name, ports, slots, group passwords, update
on start, chat toggles). **Everything** the upstream image supports works via
normal panel environment variables — add them on the server's *Startup* tab:
all game settings (`PLAYER_HEALTH_FACTOR`, `TOMBSTONE_MODE`, …, with
`GAME_SETTINGS_PRESET=Custom`), arbitrary group permissions
(`SET_GROUP_<NAME>_…`), `WEBHOOK_URL`, etc. Environment variables always win
over values hand-edited in `enshrouded_server.json`, which lives in the server
file manager alongside the saves.

## Notes & limitations

- **Stop grace:** Wings gives a signal-stopped container ~10s before SIGKILL.
  The egg stop signal triggers `enshrouded stop` (graceful save) but very large
  worlds may not finish saving in that window. The game autosaves periodically,
  so risk is limited.
- **Image-managed extras** (webhooks, scheduled restart/auto-update cron,
  `/health` endpoint) run under `enshrouded monitor`, which this egg does not
  run. To keep the server updated, enable the *Update On Start* variable.
- **`ntsync` kernel driver:** the upstream README recommends a Linux ≥6.14
  host with `/dev/ntsync`. Wings cannot pass devices into game containers, so
  Proton falls back to `fsync` — generally works, slightly less stable during
  the multithreaded Steamworks startup phase.
- **Proton requirements:** Wings's container restrictions (read-only rootfs,
  tmpfs `/tmp`) are respected by the wrapper, but this runtime path (Proton
  under a locked-down Wings sandbox) is heavier than typical eggs — give the
  server a generous memory allocation and expect a slow first boot.
