#!/usr/bin/env bash
# Add one entry to the worklog-persist config: the only sanctioned writer.
# Thin wrapper: the logic lives in config_add.py (it reads and writes YAML).
# Usage: config-add.sh project --world W --name N --repo PATH [--kb-folder F]
#        config-add.sh ignore --repo PATH
#        config-add.sh world --name W --collection C
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config_add.py" "$@"
