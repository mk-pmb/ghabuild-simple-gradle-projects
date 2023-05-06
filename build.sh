#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function build_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH" || return $?
  source -- lib/eqlines.sh --lib || return $?
  source -- lib/kisi.sh --lib || return $?

  [ -n "$GITHUB_OUTPUT" ] || local GITHUB_OUTPUT='tmp.ghout.txt'
  [ -n "$GITHUB_STEP_SUMMARY" ] || local GITHUB_STEP_SUMMARY='tmp.ghsum.txt'
  [ "$USER" == runner ] || >"$GITHUB_STEP_SUMMARY" >"$GITHUB_OUTPUT"
  exec 6>>"$GITHUB_OUTPUT" || return $?
  exec 7>>"$GITHUB_STEP_SUMMARY" || return $?

  local -A JOB=(
    [max_concurrency]=64
    [grab_ls_before_jar]='. job/ lentic/'
    )
  [ -d job ] || ln --symbolic --target-directory=. -- ../job || return $?
  source -- job/job.rc || return $?$(
    echo "E: Failed to read job description." >&2)
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
  [ "$USER" == runner ] || return 0
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



function build_verify_license () {
  local LIC="${JOB[lentic_license_sha1s]}"
  [[ "$LIC" == *[0-9a-fA-F]* ]] || return 3$(
    echo 'E: No configured for license check.' \
      'Skipping this step is not currently supported.' >&2)
  local TF='tmp.license_files.sha'
  <<<"$LIC" unindent_unblank >"$TF" || return $?
  nl -ba -- "$TF"
  cd -- lentic || return $?
  vdo sha1sum --check ../"$TF" || return $?
}


function build_generate_matrix () {
  # Drop settings that are allowed to contain newline characters:
  unset JOB[jar_add_job_files]
  unset JOB[jar_add_lentic_files]
  unset JOB[lentic_license_sha1s]

  EQLN_ADD_KEY_PREFIX='job_' eqlines_dump_dict JOB >&6 || return $?

  local V='variations.ndjson'
  [ ! -s "job/$V" ] || cat -- "job/$V" >"tmp.$V" || return $?
  V="tmp.$V"
  V="$( [ -s "$V" ] && grep -Pe '\S' -- "$V" )"
  [ -n "$V" ] || V='""'
  local N_VARI="${V//[^$'\n']/}"
  let N_VARI="${#N_VARI}+1"
  V="[ ${V//$'\n'/, } ]"
  echo "vari=$V" >&6 || return $?

  local ETA="${JOB[max_build_duration_sec_per_variation]}"
  if [ -n "$ETA" ]; then
    (( ETA = ( ETA * N_VARI ) + $EPOCHSECONDS + 1 ))
    ETA="$(date --utc --date="@$ETA" +%H:%M) UTC"
  else
    ETA='_unknown_'
  fi
  echo "eta=$ETA" >&6 || return $?

  nl -ba -- "$GITHUB_OUTPUT" || return $?
  echo "Building $N_VARI variations." \
    "This will probably finish before $ETA." >&7
}


function build_decode_variation () {
  EQLN_ADD_KEY_PREFIX='job_' eqlines_dump_dict JOB >&6 || return $?

  local -A VARI=( [variation]="$VARI" )
  VARI[java_ver]="${JOB[java_ver]:-17}"
  eqlines_read_dict VARI grpr_ <lentic/gradle.properties || return $?
  VARI[root_project_name]="$(build_detect_root_project_name)" || return $?
  VARI[artifact]="$(build_gen_artifact_name)" || return $?

  eqlines_dump_dict VARI >&6 || return $?
  local REBASH="$(local -p)"
  REBASH="${REBASH#*\(}"
  REBASH="${REBASH%\)*}"
  REBASH="${REBASH% }"
  echo "$REBASH" >tmp.variation.dict || return $?
  echo "bash_dict_pairs=$REBASH" >&6 || return $?
  nl -ba -- "$GITHUB_OUTPUT" || return $?
}


function build_detect_root_project_name () {
  local PN='s~"~~g;s~^rootProject\.name\s*=\s*~~p'
  PN="$(sed -nre "$PN" -- lentic/settings.gradle{,.*,.kts} 2>/dev/null)"
  [ -n "$PN" ] || return 4$(echo "E: $FUNCNAME: Found nothing" >&2)
  [[ "$PN" == *$'\n'* ]] && return 4$(echo "E: $FUNCNAME: Found multiple" >&2)
  echo "$PN"
}


function build_gen_artifact_name () {
  local ARTI="${JOB[artifact]}"
  case "$ARTI" in
    *'<'*'>'* )
      echo 'E: Slot names in artifact name are not supported yet.' >&4
      return 3;;
    '' ) ;; # guess.
    * ) echo "$ARTI"; return 0;;
  esac
  ARTI="${VARI[root_project_name]}-v${VARI[grpr_version]}"

  ARTI+="$(version_triad_if_set "${VARI[grpr_minecraft_version]}" -mc
    )" || return $?

  ARTI+="-$(date --utc +'%y%m%d-%H%M%S')"
  ARTI="${ARTI,,}.jar"
  echo "$ARTI"
}


function version_triad_if_set () {
  local VER="$1"; shift
  local PREIX="$1"; shift
  local SUFFIX="$1"; shift
  case "$VER" in
    '' ) return 0;;
    [0-9]*.*.* ) ;;
    [0-9]*.* ) VER+='.0';;
    * ) echo "E: Unexpected original version string format!" >&2; return 3;;
  esac
  echo "$PREIX$VER$SUFFIX"
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


function build_grab () {
  local NLF='tmp.new_lentic_files.txt'
  find_vsort lentic/ -mindepth 1 -type d -name '.*' -prune , \
    -newer tmp.variation.dict -print | cut -d / -sf 2- >"$NLF" || return $?
  ghstep_dump_file 'Newly created lentic files' text "$NLF" || return $?

  local JAR_DEST='jar-unpacked'
  mkdir --parents "$JAR_DEST"
  vdo nice_ls -- ${JOB[grab_ls_before_jar]} || true
  vdo build_jar_add_extra_files lentic || return $?
  vdo build_jar_add_extra_files job || return $?

  local JAR_DIR='lentic/build/libs'
  local JAR_LIST='tmp.jars.txt'
  find_vsort "$JAR_DIR" -maxdepth 1 -type f -name '*.jar' \
    -printf '%f\n' >"$JAR_LIST" || return $?
  ghstep_dump_file 'JARs found before filtering' text "$JAR_LIST" || return $?
  local ITEM=
  for ITEM in job/jar_filter{/[0-9]*,}.{sed,sh}; do
    [ -f "$ITEM" ] || continue
    if [ -x "$ITEM" ]; then
      vdo "$ITEM" "$JAR_LIST" || return $?
      continue
    fi
    case "$ITEM" in
      *.sed ) vdo sed -rf "$ITEM" -i -- "$JAR_LIST" || return $?;;
      *.sh ) vdo bash -- "$ITEM" "$JAR_LIST" || return $?;;
      * ) echo "E: unsupported filename extension: $ITEM" >&2; return 3;;
    esac
  done
  unzip -d "$JAR_DEST" -- "$JAR_DIR/$(grep -Pe '^\w' -- "$JAR_LIST"
    )" || return $?
  vdo find_vsort "$JAR_DEST" || return $?
}


function build_jar_add_extra_files () {
  local SRC_DIR="$1"
  local LIST=()
  readarray -t LIST < <(unindent_unblank <<<"${JOB[jar_add_${SRC_DIR}_files]}
      " | sed -re 's!\s+(->)\s+! \1 !g')
  local SRC_FILE= DEST_FILE=
  for SRC_FILE in "${LIST[@]}"; do
    DEST_FILE="$JAR_DEST/${SRC_FILE##* -> }"
    SRC_FILE="$SRC_DIR/${SRC_FILE% -> *}"
    mkdir --parents -- "$(dirname -- "$DEST_FILE")"
    cp --verbose --no-target-directory -- "$SRC_FILE" "$DEST_FILE" || return $?
  done
}








build_init "$@"; exit $?
