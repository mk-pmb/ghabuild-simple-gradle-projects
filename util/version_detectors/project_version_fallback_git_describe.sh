#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
set -o pipefail -o errexit
cd -- lentic
PROJ_VER="$(git describe --tags --abbrev=0)"
cd ..
GP='lentic/gradle.properties'
./build.sh --bypass-mutex ensure_file_has_final_newline "$GP"
PROJ_VER+='-gha'
echo "Detected project version: '$PROJ_VER' (detector pid: $$)" >&2
RGX='^version\s*=\s*'
if grep -qPe "$RGX" -- "$GP"; then
  sed -re "s~($RGX)"'.*$~\1'"$PROJ_VER~" -i -- "$GP"
else
  echo "version = $PROJ_VER" >>"$GP"
fi
