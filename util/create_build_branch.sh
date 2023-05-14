#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function create_build_branch () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH"/.. || return $?

  local -A MEM=() JOB=()
  local CLUE=
  for CLUE in "$@"; do
    interpret_clue || return 0
  done
  [ -n "${MEM[branch]}" ] || return 4$(
    echo "E: Failed to guess a branch name from the clues given." >&2)
  [ -n "${JOB[lentic_url]}" ] || return 4$(
    echo "E: Failed to guess the lentic_url." >&2)

  check_repo_clean || return $?

  git checkout -b "${MEM[branch]}" || return $?
  git reset --hard base-for-build-branches || return $?
  ( echo '# -*- coding: utf-8, tab-width: 2 -*-'
    echo
    dfjobval estimated_build_duration_per_variation '7–10 minutes'
    dfjobval max_build_duration_sec_per_variation '$(( 10 * 60 ))'
    dfjobval lentic_url
    dfjobval lentic_ref
    dfjobval lentic_license_sha1s
    dfjobval jar_add_lentic_files 'LICENSE -> LICENSE.txt'
    <<<"${JOB[+]}" sed -nre 's~$~\x27~;s~^(\S+)\s+~JOB[\1]=\x27~p'
  ) >job.rc || return $?
  git add job.rc || return $?
  git diff HEAD || return $?
}



function check_repo_clean () {
  local ACCEPT='
    /^.. util\/create_build_branch\.sh$/d
    '
  local UNCLEAN="$(git status --short | sed -rf <(echo "$ACCEPT") )"
  [ -n "$UNCLEAN" ] || return 0
  echo 'E: Flinching: Cannot deal with these unmodified changes:' >&2
  nl -ba <<<"$UNCLEAN" >&2
  return 3
}



function dfjobval () {
  local K="$1"
  local V="${JOB[$K]:-$2}"
  local Q="'"
  case "$V" in
    '$(( '*' ))' ) Q=;;
  esac
  echo "JOB[$K]=$Q$V$Q"
}


function interpret_clue () {
  case "$CLUE" in
    https://github.com/* ) interpret_clue_github || return $?;;
    fab ) build_subdir fabric || return $?;;
    * ) echo "E: Did not understand clue '$CLUE'." >&2; return 3;;
  esac
}


function build_subdir () {
  local S="$1"
  local B="${MEM[branch]}"
  git branch | cut -b 3- | grep -qxFe "$B" && git branch -m "$B" "$B/all"
  B+="/$S"
  MEM[branch]="$B"
  JOB[+]+=$'\n'"lentic_jar_dir $S/build/libs"
}


function trim_prefix () {
  local K="$1" S="$2" V=
  eval 'V=$'"$K"
  [[ "$V" == *"$S"* ]] || eval "$K="
  eval "$K=${V#*$S}"
}


function interpret_clue_github () {
  local GH_BASE_URL='https://github.com/'
  CLUE="${CLUE:${#GH_BASE_URL}}"
  MEM[gh_user]="${CLUE%%/*}"; trim_prefix CLUE /
  MEM[gh_repo]="${CLUE%%/*}"; trim_prefix CLUE /
  case "$CLUE" in
    / | '' ) ;;
    tree/* ) JOB[lentic_ref]="${CLUE#tree/}";;
  esac
  local U_R="${MEM[gh_user]}/${MEM[gh_repo]}"
  JOB[lentic_url]="$GH_BASE_URL$U_R.git"
  MEM[branch]="build-gh/${U_R,,}"
}










create_build_branch "$@"; exit $?
