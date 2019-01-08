#!/usr/bin/env bash

set -e

for bats_file in $(find test -name "*.bats"); do
  echo "=> $bats_file"
  bats "$bats_file"
done
