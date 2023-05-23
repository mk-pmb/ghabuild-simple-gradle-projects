#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
set -o pipefail -o errexit
cd -- lentic
PROJ_VER="$(git describe --tags --abbrev=0)"
echo "Detected project version: '$PROJ_VER'" >&2
sed -re 's~^(version\s*=\s*).*$~\1'"$PROJ_VER-gha~" -i -- gradle.properties
