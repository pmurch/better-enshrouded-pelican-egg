# Runbook: Enshrouded on Pelican

Operational knowledge for debugging this egg + image. **Keep it current** — see
`AGENTS.md`. Add a dated entry to the incident log whenever you learn
something new.

## How a boot works

1. Wings starts `ghcr.io/pmurch/enshrouded-pelican:latest` (uid 999, read-only
   rootfs, volume at `/home/container`, no Cmd override, no `/dev/ntsync`).
2. `pelican-init.sh` (ENTRYPOINT): sets `XDG_RUNTIME_DIR`, links `~/.steam/root`,
   starts Xvfb on `:0`, bootstraps SteamCMD if uncached, then execs the base
   image's `entrypoint.sh`, which runs `scripts.d` hooks (`10-wine-init`,
   `20-proton-init`).
3. `pelican-start.sh` (CMD) runs Wings' `$STARTUP` (from the egg) with
   `[egg] phase N/4` markers: `enshrouded setup` → `enshrouded install` →
   `enshrouded start` → `tail` of `logs/server.log`, `logs/server.err`,
   `logs/enshrouded_server.log`.
4. `enshrouded start` (upstream Rust CLI) spawns `dockerify run --proton
   enshrouded_server.exe`, which runs Proton's `run` verb (via `steam.exe`).
5. Pelican marks the server online when the console prints
   `[Session] 'HostOnline' (up)!` (egg `config.startup.done`).

## Healthy signs

- Memory ≈ 1 GB+ once the game is loaded. **A few hundred MB means
  `enshrouded_server.exe` never started** (only Wine/Proton helpers are up).
- `logs/enshrouded_server.log` has content; `HostOnline` appears.

## Triage

| Symptom | Likely cause / action |
|---|---|
| Stuck at phase 2, quiet | First-boot download (~8 GB). Check host disk. |
| `[egg] ERROR: enshrouded_server.exe is not running` (or phase 4 reached, no `HostOnline`, low memory) | Read `steam-2278520.log` (server root). If it ends after `steamclient_init_registry Failed to connect to Steam` with no game output, the game is launched but silent: raise `WINEDEBUG` (see env table) to see where it stalls. `winebth ZwLoadDriver c0000142` is benign. |
| `server.err` full of DXVK / llvmpipe / EDID lines | Noise from Proton's `xalia.exe`, **not** the server. Harmless; disabled via `PROTON_USE_XALIA=0`. |
| `ProtonFixes … unit test` warnings | Normal. ProtonFixes only runs for the `waitforexitandrun` verb; upstream uses `run`. |
| Died on a foreign/newer Wine prefix | System wine touched Proton's prefix. `WINEPREFIX` must stay `~/.wine`; Proton uses `$STEAM_COMPAT_DATA_PATH/pfx`. Use panel **Reinstall** to wipe `.proton`. |
| Image changes not taking effect | CI only builds on push to `main`, `v*` tags, weekly cron, or manual dispatch. A feature-branch push does **not** rebuild. |

## Key environment (see `image/Dockerfile`)

| Var | Why |
|---|---|
| `PROTON_NO_FSYNC=1`, `WINEFSYNC=0` | No `/dev/ntsync` under Wings; fsync fallback is unstable at startup. Egg variable `PROTON_NO_FSYNC` overrides. Console shows `wineserver: using server-side synchronization` when active. |
| `SteamAppId` / `SteamGameId` = `2278520` | Upstream's launcher sets neither. Proton writes **no** debug log without `SteamGameId`, and Wine output then spills into `server.err`. Also gives Steamworks an app id. |
| `WINEDEBUG` (egg variable) | Default `fixme-all`. For stalls set `fixme-all,+loaddll,+process,+timestamp`; output lands in `steam-2278520.log`. |
| `PROTON_USE_XALIA=0` | Headless server doesn't need Xalia; removes spurious Vulkan startup. |
| `HOME`, `STEAM_COMPAT_*`, `WINEPREFIX` → `/home/container/...` | Everything writable must live on the volume. |

## Diagnostics

Inside the container (`docker exec -it <id> bash` on the Wings host):

```bash
ps -eo pid,ppid,etime,rss,args | grep -Ei 'enshrouded|wine|proton|xalia' | grep -v grep
tail -n 100 /home/container/steam-2278520.log
ls -la /home/container/logs/
```

Inspecting upstream locally (large pull):

```bash
docker pull --platform linux/amd64 mbround18/enshrouded-docker:proton-latest
docker run --rm --platform linux/amd64 --entrypoint sh mbround18/enshrouded-docker:proton-latest -c '<cmd>'
```

Proton launcher: `/home/steam/.steam/root/compatibilitytools.d/current/proton`
(`run()` ≈ line 2809, `setup_logging()` ≈ line 2121). Upstream scripts:
`/opt/steamcmd-bases/scripts.d/`. Launch binary: `/opt/steamcmd-bases/bin/dockerify`.

## Release procedure

1. Edit `image/` and/or `egg-enshrouded-mbround18.json`.
2. Push to `main` (or merge) — CI "Build and publish image" takes ~30 s.
3. Confirm: `gh run list --repo pmurch/better-enshrouded-pelican-egg --limit 1`.
4. Restart the server in Pelican (Wings pulls the new `latest` digest).
5. Egg JSON changes also require re-importing the egg in the panel.

## Incident log

- **2026-10-25 — boots reach phase 4 but never go online.** Ruled out: wrapper
  bugs (phases all run), fsync (disabled, confirmed in log), DXVK/llvmpipe
  (output is from `xalia.exe`). Found: upstream never sets `SteamGameId`, so no
  Proton log exists. Fix shipped: `SteamAppId`/`SteamGameId=2278520`,
  `PROTON_USE_XALIA=0` (commit `62d3ddc`). **Outcome: unverified** — update
  this entry with the result after the next server restart
  (`steam-2278520.log` should now exist).
- **2026-10-25 (later) — first real Proton log.** `steam-2278520.log` now
  exists. It shows `Command: ['/home/steam/enshrouded/enshrouded_server.exe']`,
  options `gamedrive forcelgadd nofsync`, benign `winebth` driver error, then
  `steamclient_init_registry Failed to connect to Steam` and nothing more;
  `server.log` empty, `server.err` only ProtonFixes warnings (Xalia noise gone,
  so `PROTON_USE_XALIA=0` worked). Local check (arm64 host, amd64 image under
  emulation): Proton + Wine launch a trivial exe in ~3 s with the same env, so
  the base environment is sound. **Still unknown** why the server is silent and
  small in memory. Next step: `WINEDEBUG=fixme-all,+loaddll,+process,+timestamp`
  and read the log.
- **2026-10-25 (later still) — root symptom identified.** With
  `+loaddll,+process,+timestamp`, `steam-2278520.log` shows
  `enshrouded_server.exe` (pid 0130) launching, loading `steam_api64.dll`,
  `winex11.drv`, `msacm32`, `winmm`, `wsock32`, then calling
  `NtTerminateProcess exit_code -1` ~140 ms after start; Proton then exits too.
  **The server is not hung — it exits immediately** (no SEH crash trace, so a
  deliberate `exit(-1)`), which is why CPU/memory are flat. `Failed to connect
  to Steam` precedes it but is not proven to be the cause. The console's
  `tail -c0` was hiding the game's own `logs/enshrouded_server.log`; startup now
  tails the last 40 lines and prints an ERROR 45 s after launch if the process
  is gone. **Next:** read `logs/enshrouded_server.log` and
  `enshrouded_server.json` from the server root.
