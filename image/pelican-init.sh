#!/bin/bash
# PID 1 chain step 1: runs before the base image's init hooks.
# Nothing privileged is needed today (Wings runs containers as root by
# default); this hook exists so the base image's ENTRYPOINT can be kept
# untouched in the chain.
set -Euo pipefail

exec /opt/steamcmd-bases/entrypoint.sh "$@"
