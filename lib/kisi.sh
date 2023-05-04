#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function vdo () {
  echo "=== run: $* ==="
  SECONDS=0
  "$@" |& tee -- $VDO_TEE
  local RV="${PIPESTATUS[*]}"
  let RV="${RV// /+}"
  echo "=== done: $*, rv=$RV, took $SECONDS sec ==="
  return $RV
}


function fmt_markdown_details_file () {
  echo "<details><summary>$1</summary>"
  shift
  echo
  echo '```'"$1"
  shift
  sed -re '/^\x60{3}/s~^.~\&#96;~' -- "$@"
  echo '```'
  echo
  echo "</details>"
  echo
}


function ghstep_dump_file () {
  fmt_markdown_details_file "$@" >>"$GITHUB_STEP_SUMMARY" || return $?
}


function status_report_tall_gapped_on_ci () {
  local M='+success'
  [ "$1" == 0 ] || M="-FAIL! rv=$1"
  local B="${M:0:1}"
  M="# ${M:1} # $GITHUB_REF = $GITHUB_SHA #"
  M="${M//#/#####}"
  M="${M//#/$B}"
  if [ "$USER" == runner -a "$1" != 0 ]; then
    M="~~~$M"$'\n~~~~~~~~~~~~~~~~~~~~'
    M="${M//\~/$B$'\n'}"
  fi
  echo "$M"
}


function read_build_matrix_entry () {
  local SED='
    s~^ *"([^"]+)": ~\1\n~
    /\n/!d
    s~,$~~
    s~\x22|\x27~~g
    s~^~[\x27~
    s~\n~\x27]=\x27~
    s~$~\x27~
    '
  eval "MX=( $(sed -rf <(echo "$SED") -- tmp.matrix_entry.json) )"
}












[ "$1" == --lib ] && return 0; "$@"; exit $?
