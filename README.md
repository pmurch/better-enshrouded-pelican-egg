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
3. The container runs as the Wings-configured UID (`system.user.uid`, seen in
   practice as `999` / user `container`), not the image's `steam` user — which
   pairs fine with the above since all writes go to the mounted volume.

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

Wings can only *pull* images — neither Wings nor an egg's install script can
build one (the install script itself runs inside a sandboxed installer
container with no Docker access). So the wrapper image must exist either in a
registry or locally on the Wings host:

1. **Build the image.** Either:
   - push this repo to GitHub — the included Action publishes
     `ghcr.io/<your-org>/enshrouded-pelican:latest` (no secrets needed; the
     default `GITHUB_TOKEN` has registry write). Wings re-checks the tag on
     every boot, so servers pick up image updates automatically; or
   - build it on the Wings host once:
     `docker build -t enshrouded-pelican ./image`
     and reference it in the egg as `~enshrouded-pelican:latest` — the `~`
     prefix tells Wings it is a local image and to skip pulling. Manual
     rebuilds required on upstream changes; only works on that host.
2. **Import the egg** in the panel (Nests → Import). The `docker_images`
   entry already points at `ghcr.io/pmurch/enshrouded-pelican:latest` built by
   this repo's Action (change it if you fork/rename; use the `~`-prefixed
   local name if you built locally).
3. **Create a server** with **2 allocations**, both TCP+UDP: `15636` (game)
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
`GAME_SETTINGS_PRESET=Custom`) and arbitrary group permissions
(`SET_GROUP_<NAME>_…`). Environment variables always win
over values hand-edited in `enshrouded_server.json`, which lives in the server
file manager alongside the saves.

## Events & player counts

The startup runs `enshrouded monitor` in the background (output silenced; the
console stays focused on the game log). This powers:

- **Webhooks** — set *Webhook URL* (e.g. a Discord webhook) to receive
  server started / stopping / stopped and player joined / left events.
  For non-Discord endpoints (n8n, custom HTTP), the payload is plain JSON:
  `{"notification_type": "<server name>: Player Joined", "message": "Player
  Alice has joined the adventure!", "data": null}` — the player name is only
  in `message`, so parse it there. The endpoint must respond 2xx; a delivery
  failure kills the webhook watcher thread until the next restart (the game
  server itself is unaffected). Leave `STOP_DELAY` unset — Wings' ~10s stop
  grace cannot absorb it.
- **Health endpoints** — `/live`, `/ready`, `/health` on *Health Port*
  (default 3000, `0` disables). Not visible through Wings; reach it via an
  allocation on the Wings network or port-forward if you monitor externally.
- **`AUTO_UPDATE` / `SCHEDULED_RESTART`** — now functional; set them as custom
  environment variables on the Startup tab (cron expressions via
  `AUTO_UPDATE_SCHEDULE` / `SCHEDULED_RESTART_SCHEDULE`). Prefer the panel's
  own *Schedules* feature where possible — Wings learns about those restarts.

**Player counts are not shown in the panel and cannot be pushed to it**:
neither Wings nor the Pelican panel models a player count (Wings reports only
CPU/RAM/disk; there is no "players" field or API to update one — same is true
of Pterodactyl). Join/leave lines are visible live in the server console
(the game writes them to its session log, which the egg tails). For a real
player-count feed, poll the **Steam query port** (the *Query Port* allocation,
UDP): the server answers standard server queries with name, players, and max
slots. Tools like `gamedig` (`gamedig --type protocol --host IP --query-port
15637`) or any game-server exporter (Prometheus/Grafana, server-browser sites)
read it directly — no panel integration needed. If you want webhook events
somewhere other than Discord, point *Webhook URL* at any HTTP endpoint that
accepts Discord-format embed payloads.


## Troubleshooting

- **Is it stuck or just downloading?** The first boot downloads the dedicated
  server (several GB) and SteamCMD reports progress with carriage returns
  *inside captured output* — the panel console can look frozen for minutes at
  `steamcmd.sh: Starting ... steamcmd`. The `[egg] phase N/4:` markers now
  show exactly where the boot is; if phase 2 is the quiet one, check free
  disk space on the Wings host — if it's shrinking, it's downloading.
- **Server reaches phase 4 but never prints `HostOnline`** — the game's own
  stdout/stderr are redirected by the CLI to `logs/server.log` /
  `logs/server.err` (visible in the panel file manager and now followed by
  the console). A classic cause was fixed in the wrapper: Proton must build
  its own prefix (`~/.proton/pfx`, via `STEAM_COMPAT_DATA_PATH`); if the
  system wine is allowed to `wineboot` that same directory first, Proton's
  bundled wine dies on the foreign prefix. Do a panel **Reinstall** (wipes
  `.proton`) once after upgrading from an older wrapper image so the tainted
  prefix is gone. GE-Proton also writes `$HOME/steam-2278520.log` crash logs
  when enabled — check the server root in the file manager.
- **Panel Reinstall now means something.** Wings runs the egg's install
  script with the server volume mounted at `/mnt/server`, so reinstall wipes
  the only state that can end up half-built — the SteamCMD bootstrap cache
  (`.local`, `.steam`, `Steam`) and the Wine/Proton prefix (`.proton`) — and
  the next boot rebuilds them from scratch. Saved games (`savegame/`),
  `enshrouded_server.json`, and the game files are untouched. For a *full*
  redo (fresh game download too), also delete `enshrouded_server.exe` in the
  file manager. Note: reinstall never affects the Docker image — Wings
  re-resolves the image tag at every container start anyway.
- **Image freshness:** the Action rebuilds this image weekly (so it tracks
  upstream `mbround18/enshrouded-docker:proton-latest`) and on every push;
  Wings pulls the new digest automatically at the next server start.
- **`Read-only file system` lines from `00-common-init.sh` / `99-cleanup.sh`**
  were removed in the wrapper by deleting those two hooks; if you see them,
  you're running an older image tag.

## Notes & limitations

- **Stop grace:** Wings gives a signal-stopped container ~10s before SIGKILL.
  The egg stop signal triggers `enshrouded stop` (graceful save) but very large
  worlds may not finish saving in that window. The game autosaves periodically,
  so risk is limited.
- **`ntsync` kernel driver:** the upstream README recommends a Linux ≥6.14
  host with `/dev/ntsync`. Wings cannot pass devices into game containers, so
  Proton falls back to `fsync` — generally works, slightly less stable during
  the multithreaded Steamworks startup phase.
- **Proton requirements:** Wings's container restrictions (read-only rootfs,
  tmpfs `/tmp`) are respected by the wrapper, but this runtime path (Proton
  under a locked-down Wings sandbox) is heavier than typical eggs — give the
  server a generous memory allocation and expect a slow first boot.
