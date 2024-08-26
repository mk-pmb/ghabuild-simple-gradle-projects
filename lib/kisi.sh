#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


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


function find_vsort () {
  local P='sort --version-sort' V=
  if [[ "$1" == --curdirs=[0-9]* ]]; then
    V="${1#*=}"
    shift
    (( V += 1 ))
    P="cut -d / -sf $V- | $P"
  fi
  if [ "$1" == --unique ]; then P+=" $1"; shift; fi
  find "$@" > >(eval "$P")
}


function unindent_unblank () { sed -nre 's~^\s*(\S)~\1~p' -- "$@"; }


function dump_bash_dict_pairs () {
  local PAIRS="$(declare -p | grep -Pe '^declare -\w*A\w* '"$1"'=\(')"
  # ^-- The \w* are because GHA's bash @2023-05-06 had -Ax,
  #     albeit the bash on my Ubuntu only gave -A.
  [ -n "$PAIRS" ] || return 4$(echo "E: $FUNCNAME: no such dict: $1" >&2)
  PAIRS="${PAIRS#*\(}"
  PAIRS="${PAIRS%\)*}"
  PAIRS="${PAIRS# }"
  PAIRS="${PAIRS% }"
  [ -z "$PAIRS" ] || echo "$PAIRS"
}


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
