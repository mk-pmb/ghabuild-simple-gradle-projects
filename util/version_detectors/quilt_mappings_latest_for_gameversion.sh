#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

function quilt_mappings_latest_for_gameversion () {
  local GAME_VER="$1" # e.g. '1.20.4' or '1.21'
  [ -n "$GAME_VER" ] || return 2$(
    echo E: $FUNCNAME: 'Missing CLI argument: game version' >&2)
  local REPO_URL='https://github.com/QuiltMC/quilt-mappings.git'
  local SED_PARSE='
    s!-build-number-!\n!
    /\n/!b
    s~^\S+\s+refs/tags/build/refs/heads/~\f~
    s~^\f(\S+)\n([0-9]+)$~< \1 >\2~p
    '
  local BNUM="$( git ls-remote "$REPO_URL" | sed -nrf <(echo "$SED_PARSE") )"
  [ -n "$BNUM" ] || return 4$(
    echo E: $FUNCNAME: 'Found no parseable tag names at all!' >&2)
  BNUM="$(<<<"$BNUM" grep -m 2 -Fe "< $GAME_VER >")"
  case "$BNUM" in
    '' )
      echo E: $FUNCNAME: >&2 "Found no tag name for game version: $GAME_VER"
      return 5;;
    *'<'*'<'* )
      echo E: $FUNCNAME: >&2 \
        "Found too many tag names for this game version: $GAME_VER"
      return 6;;
    '<'*'>'* ) echo "${BNUM##*>}"; return $?;;
  esac
  echo E: $FUNCNAME: >&2 \
    "Lookup failure. Probably unknown game version: '$GAME_VER'"
  return 7
}

quilt_mappings_latest_for_gameversion "$@"; exit $?
