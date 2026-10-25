# Agent instructions (AGENTS.md)

This repo packages mbround18/enshrouded-docker as a Pelican/Wings egg
(`egg-enshrouded-mbround18.json`) plus a wrapper image (`image/`).

## Always keep `docs/RUNBOOK.md` current

Treat the runbook as part of every change, not an afterthought. In the same
commit as the change:

- Changed `image/`, the egg JSON, or CI? Update the affected runbook sections
  (boot flow, env table, triage table, release procedure).
- Learned something while debugging (a ruled-out cause, a log's real meaning,
  a wrong assumption)? Add or correct a triage row and add a dated entry to the
  **Incident log** with the outcome. Correct earlier wrong advice rather than
  leaving it.
- Mark conclusions as *verified* or *unverified*. After a fix ships, record
  the real result once the user reports it.
- Keep `README.md` troubleshooting consistent with the runbook; the runbook is
  the detailed source.

## Working rules

- CI builds only on push to `main`, `v*` tags, the weekly cron, or manual
  dispatch. Pushing a feature branch does not rebuild the image; say so and ask
  before merging/pushing to `main`.
- Never claim a fix works until the user confirms on their server; the game
  can't be run locally (needs the ~8 GB server download and Wings' sandbox).
- Don't guess from log noise: identify which process emitted a line first.
