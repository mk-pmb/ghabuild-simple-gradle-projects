#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
# This script is meant to help import a job.rc
# from a job branch into experimental.

function import_job_rc () {
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH"/.. || return $?

  local ACCEPTABLE_SOURCE_BRANCHES='^(build|debug)-'
  git branch --show-current | grep -Pe "$ACCEPTABLE_SOURCE_BRANCHES" \
    && return 3$(echo "E: You're on an actual job branch." >&2)

  mkdir --parents job
  cd -- job || return $?
  local BRAN="$(
    git branch --list --format='%(refname:lstrip=2)' --sort=version:refname \
    | grep -Pe "$ACCEPTABLE_SOURCE_BRANCHES" | grep -Fe "$1")"
  BRAN="${BRAN//$'\n'/ }"
  case "$BRAN" in
    '' ) echo "E: Found no matching branch!" >&2; return 3;;
    *' '* )
      echo "W: Found multiple matching branches: $BRAN." >&2
      BRAN="${BRAN##* }"
      ;;
  esac
  echo "D: Importing job.rc from $BRAN." >&2
  >>job.rc
  mv --no-target-directory -- {,old_}job.rc || return $?
  git show "$BRAN":job.rc >job.rc || return $?
  colordiff -sU 1 -- {old_,}job.rc || true
}



import_job_rc "$@"; exit $?
