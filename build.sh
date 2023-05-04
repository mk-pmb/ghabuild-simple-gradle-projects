#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function build_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH" || return $?
  source -- lib/kisi.sh --lib || return $?

  exec 6>>"$GITHUB_OUTPUT" || return $?
  local -A JOB=()
  [ -d job ] || ln --symbolic --target-directory=. -- ../job || return $?
  source -- job/job.rc || return $?
  # local -p

  local TASK="$1"; shift
  build_"$TASK" "$@" && return 0
  local RV=$?
  echo :
  echo "E: Build task $TASK failed, rv=$RV"
  yes : | head --lines=15
  return "$RV"
}


function build_git_basecfg () {
  local C='git config --global'
  $C user.name 'CI'
  $C user.email 'ci@example.net'
  $C init.defaultBranch default_branch
}


function build_clone_lentic_repo () {
  if [ -f lentic/.git/config ]; then
    echo 'Skip cloning: Repo lentic already exists.'
    return 0
  fi
  vdo git clone --single-branch --branch="${JOB[lentic_ref]}" \
    -- "${JOB[lentic_url]}" lentic || return $?

  chmod a+x -- lentic/gradlew || return $?
  # ^-- Some repos don't have +x. Maybe their maintainers use Windows.
}


function build_generate_matrix () {
  # build_clone_lentic_repo || return $?
  echo "conc=${JOB[max_concurrency]:-64}" >&6 || return $?

  local V='variations.ndjson'
  [ ! -s "job/$V" ] || cat -- "job/$V" >"tmp.$V" || return $?
  V="tmp.$V"
  V="$( [ -s "$V" ] && grep -Pe '\S' -- "$V" )"
  [ -n "$V" ] || V='""'
  V="[ ${V//$'\n'/, } ]"
  echo "vari=$V" >&6 || return $?

  nl -ba -- "$GITHUB_OUTPUT" || return $?
}


function build_decode_variation () {
  local VARI="$VARI"
  sed -nre 's~^\s+~~;/\S/p' <<<"
    vari=$VARI
    java=${JOB[java_ver]:-17}
    " >&6 || return $?
  nl -ba -- "$GITHUB_OUTPUT" || return $?
}


function build_gradle () {
  cd -- lentic || return $?
  local GW_OPT=(
    --stacktrace
    --info
    --scan
    )
  vdo ./gradlew clean "${GW_OPT[@]}" || true
  local GR_LOG='../tmp.gradlew.log'
  VDO_TEE="$GR_LOG" vdo ./gradlew build "${GW_OPT[@]}" && return 0
  local GR_RV=$?

  local GR_HL='../tmp.gradlew.hl.log'
  "$SELFPATH"/lib/gradle_log_highlights.sed "$GR_LOG" | tee -- "$GR_HL"
  fmt_markdown_details_file "Gradle failed, rv=$GR_RV" text "$GR_HL" \
    >>"$GITHUB_STEP_SUMMARY"

  return "$GR_RV"
}








build_init "$@"; exit $?
