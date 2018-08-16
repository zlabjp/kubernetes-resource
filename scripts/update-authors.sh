#!/usr/bin/env bash

set -e -o pipefail

SCRIPT_ROOT="$(dirname "${BASH_SOURCE}")/.."
AUTHORS_FILE="${AUTHORS_FILE:-"${SCRIPT_ROOT}/AUTHORS"}"

cat <<EOL > "$AUTHORS_FILE"
List of contributors
====================

$(git log  --format='%at,%an' | sort -t, -n | awk -F, '{if (!a[$2]++) print $2;}')
EOL
