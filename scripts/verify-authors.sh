#!/usr/bin/env bash

set -e -o pipefail

SCRIPT_ROOT="$(dirname "${BASH_SOURCE}")/.."
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap "cleanup" EXIT SIGINT

export AUTHORS_FILE="${TMP_ROOT}/AUTHORS"
"${SCRIPT_ROOT}/scripts/update-authors.sh"

ret=0
diff "${SCRIPT_ROOT}/AUTHORS" "$AUTHORS_FILE" || ret=$?

if [[ $ret -eq 0 ]]; then
  echo "AUTHORS is up to date."
else
  echo "AUTHORS is out of date. Please run scripts/update-authors.sh."
  exit 1
fi
