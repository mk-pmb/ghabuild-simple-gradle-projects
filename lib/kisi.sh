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
  local TITLE="$1"; shift
  local FMT="$1"; shift
  local FILE="$1"; shift
  local OPT="$1"; shift
  [ -n "$OPT" ] || case "$FILE" in
    *.txt ) OPT='--count-lines';;
  esac
  case "$OPT" in
    '' ) ;;
    --count-lines ) TITLE+=" ($(wc --lines <"$FILE") lines)";;
    * ) echo "E: $FUNCNAME: Unsupported option: $OPT"; return 3;;
  esac
  echo "<details><summary>$TITLE</summary>"
  echo
  echo '```'"$FMT"
  sed -re '/^\x60{3}/s~^.~\&#96;~' -- "${FILE:-/dev/stdin}"
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


function find_vsort () { find "$@" > >(sort --version-sort); }
function unindent_unblank () { sed -nre 's~^\s*(\S)~\1~p' -- "$@"; }


function nice_ls () {
  local LS_OPT=(
    --file-type
    --format=long
    --human-readable
    --group-directories-first
    )
  ls "${LS_OPT[@]}" "$@" || return $?
}











[ "$1" == --lib ] && return 0; "$@"; exit $?
