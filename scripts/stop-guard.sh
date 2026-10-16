#!/usr/bin/env bash
# Stop hook for worklog-persist.
#
# Reads the Stop-hook JSON on stdin and prints {"decision":"block","reason":...}
# to force one more turn when work was committed, pushed or shipped since the last Outline
# write; prints nothing otherwise. Thin wrapper: the logic lives in stop_guard.py.
#
# Always exits 0. An internal error must allow the stop, never crash the session.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$here/stop_guard.py" || true
exit 0
