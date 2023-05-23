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

  local -A MEM=()
  local -A JOB=(
    [max_concurrency]=64
    [grab_ls_before_jar]='. job/ lentic/'
    [lentic_jar_dir]='build/libs'
    [github_jobmgmt_dura_sec]=30  # for setting up the job, cleanup tasks etc.
    [total_dura_tolerance_sec]=30 # tolerance for e.g. rounding errors.
    )
  [ -d job ] || ln --symbolic --target-directory=. -- ../job || return $?
  source -- job/job.rc || return $?$(
    echo "E: Failed to read job description." >&2)

  local -A VARI=()
  [ ! -f tmp.variation.dict ] || eval "VARI=(
    $(cat -- tmp.variation.dict) )" || return $?
  # local -p

  local TASK="$1"; shift
  build_"$TASK" "$@" && return 0
  local RV=$?
  echo :
  echo "E: Build task $TASK failed, rv=$RV"
  yes : 2>/dev/null > >(head --lines=15)
  wait # for head to finish printing
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

  local K= V=
  for K in "${!JOB[@]}"; do
    case "$K" in
      job_* )
        echo "E: Job option '$K' seems to have an accidential prefix." >&2
        return 3;;
    esac
  done

  EQLN_ADD_KEY_PREFIX='job_' eqlines_dump_dict JOB >&6 || return $?

  V='variations.ndjson'
  [ ! -s "job/$V" ] || cat -- "job/$V" >"tmp.$V" || return $?
  V="tmp.$V"
  V="$( [ -s "$V" ] && grep -Pe '\S' -- "$V" )"
  [ -n "$V" ] || V='""'
  local N_VARI="${V//[^$'\n']/}"
  let N_VARI="${#N_VARI}+1"
  V="[ ${V//$'\n'/, } ]"
  echo "vari=$V" >&6 || return $?
  build_predict_eta >&6 || return $?

  nl -ba -- "$GITHUB_OUTPUT" || return $?
  echo "Building $N_VARI variations." \
    "This will probably finish before ${MEM[eta_hr]}." >&7
}


function build_predict_eta () {
  [ "${N_VARI:-0}" -ge 1 ] || return 3$(
    echo "E: $FUNCNAME: Bad N_VARI='$N_VARI'" >&2)

  local OPT='max_build_duration_sec_per_variation'
  local PER_VARI="${JOB[$OPT]}"
  echo "D: $FUNCNAME: original PER_VARI='$PER_VARI'" >&2
  if [ -z "$PER_VARI" ]; then
    echo 'eta=_unknown_'
    return 0
  fi
  [ "$PER_VARI" -ge 1 ] || return 4$(
    echo "E: $FUNCNAME: Invalid value for option $OPT!" >&2)

  let "PER_VARI+=${JOB[github_jobmgmt_dura_sec]}"
  local DURA_TOL="${JOB[total_dura_tolerance_sec]}"
  local DURA_ESTIM=$(( ( PER_VARI * N_VARI ) + DURA_TOL ))
  local ETA=$(( EPOCHSECONDS + DURA_ESTIM ))

  local HR="$(date --utc --date="@${ETA:-0}" +'%H:%M UTC, %F')"
  local -p | sed -re "s~^~D: $FUNCNAME: ~" >&2
  MEM[eta_hr]="$HR"
  [[ "$HR" != *' 1970-'* ]] || return 4$(echo 'E: ETA calculation failed.' >&2)
  echo "eta=$HR"
  [ "${DURA_ESTIM:-0}" -ge 1 ] || return 4$(echo "E: $FUNCNAME: FUBAR!" >&2)
}


function build_decode_variation () {
  EQLN_ADD_KEY_PREFIX='job_' eqlines_dump_dict JOB >&6 || return $?

  echo "$VARI_JSON" >tmp.variation.json || return $?

  VARI=()
  VARI[java_ver]="${JOB[java_ver]:-17}"
  [ ! -f lentic/gradle.properties ] || <lentic/gradle.properties \
    eqlines_read_dict VARI grpr_ || return $?
  VARI[root_project_name]="$(build_detect_root_project_name)" || return $?
  VARI[artifact]="$(build_gen_artifact_name)" || return $?

  eqlines_dump_dict VARI >&6 || return $?
  local REBASH="$(dump_bash_dict_pairs VARI)"
  [ -n "$REBASH" ] || return 4$(echo 'E: VARI dict dump is empty!' >&2)
  echo "$REBASH" >tmp.variation.dict || return $?
  echo "bash_dict_pairs=$REBASH" >&6 || return $?
  nl -ba -- "$GITHUB_OUTPUT" || return $?
}


function build_apply_hotfixes () {
  local SCAN=()
  build_apply_hotfixes__runparts early || return $?

  build_apply_hotfixes__scan fix || return $?
  local ORIG= FIX=
  for FIX in "${SCAN[@]}"; do
    ORIG="${FIX%.fix.*}"
    ORIG="lentic/${ORIG#*/*/}"
    if [ -x "$FIX" ]; then
      vdo ./"$FIX" -i -- "$ORIG" || return $?
      continue
    fi
    vdo sed -rf "$FIX" -i -- "$ORIG" || return $?
  done

  build_apply_hotfixes__runparts late || return $?

  local MODIF="$(git status --short)"
  [ -n "$MODIF" ] || return 0
  ghstep_dump_file 'Hotfixed files' text <<<"$MODIF" || return $?

  cd -- lentic || return $?
  git add -A . || return $?
  git commit -m 'Apply hotfixes' || return $?
  cd -- "$SELFPATH" || return $?
  GIT_DIR=lentic/ git format-patch --irreversible-delete --stdout \
    'HEAD~1..HEAD' | ghstep_dump_file 'Hotfix patch' diff || return $?
  ghstep_dump_file 'Hotfix' text <<<"$MODIF" || return $?
}


function build_apply_hotfixes__scan () {
  SCAN=(
    find
    job/hotfixes/
    -type f
    '(' -false
      -o -name "*.$1.sed"
      -o -name "*.$1.sh"
      ')'
    -printf '%f\t%p\n'
    )
  readarray -t SCAN < <("${SCAN[@]}" | sort --version-sort | cut -sf 2-)
}


function build_apply_hotfixes__runparts () {
  local FIX=
  for FIX in "${SCAN[@]}"; do
    [ ! -x "$FIX" ] || vdo ./"$FIX" || return $?
  done
}


function build_detect_root_project_name () {
  local PN="$(build_detect_root_project_name__core | sort --unique)"
  local BEFORE=
  until [ "$PN" == "$BEFORE" ]; do
    BEFORE="$PN"
    PN="${PN%[/_.-]}"
  done
  case "$PN" in
    '' ) echo "E: $FUNCNAME: Found nothing" >&2; return 4;;
    *$'\n'* )
      echo "E: $FUNCNAME: Found too many names: ${PN//$'\n'/¶ }" >&2
      return 4;;
  esac
  echo "$PN"
}


function build_detect_root_project_name__core () {
  sed -nrf <(echo '
    s~"~~g;s~^rootProject\.name\s*=\s*~~p
    ') -- lentic/settings.gradle{,.*,.kts} 2>/dev/null

  sed -nrf <(echo '
    s~"~~g;s~^mod_id\s*=\s*~~p
    ') -- lentic/gradle.properties 2>/dev/null
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

  ARTI+="$(version_triad_if_set "$(build_guess_minecraft_version
    )" -mc)" || return $?

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
  [ -n "${VARI[artifact]}" ] || return 4$(echo 'E: Empty artifact name!' >&2)
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
  [ -n "${VARI[artifact]}" ] || return 4$(echo 'E: Empty artifact name!' >&2)

  local NLF='tmp.new_lentic_files.txt'
  find_vsort lentic/ -mindepth 1 -type d -name '.*' -prune , \
    -newer tmp.variation.dict -print | cut -d / -sf 2- >"$NLF" || return $?
  ghstep_dump_file 'Newly created lentic files' text "$NLF" || return $?

  local JAR_UNP='jar-unpacked'
  mkdir --parents -- "$JAR_UNP"
  vdo nice_ls -- ${JOB[grab_ls_before_jar]} || true
  vdo build_jar_add_extra_files lentic || return $?
  vdo build_jar_add_extra_files job || return $?

  local JAR_DIR="lentic/${JOB[lentic_jar_dir]}"
  local JAR_LIST='tmp.jars.txt'
  find_vsort "$JAR_DIR" -maxdepth 1 -type f -name '*.jar' \
    -printf '%f\n' >"$JAR_LIST" || true
  vdo base64 -- "$JAR_LIST"
  ghstep_dump_file 'JARs found before filtering' text "$JAR_LIST" || return $?
  if [ ! -s "$JAR_LIST" ]; then
    build_grab_found_no_jars
    return 4
  fi
  local ITEM= OPT=
  for ITEM in job/jar_filter{/[0-9]*,}.{sed,sh}; do
    [ -f "$ITEM" ] || continue
    if [ -x "$ITEM" ]; then
      case "$ITEM" in
        *.sed ) OPT='-i';;
        * ) OPT=;;
      esac
      vdo "$ITEM" $OPT "$JAR_LIST" || return $?
      continue
    fi
    case "$ITEM" in
      *.sed ) vdo sed -rf "$ITEM" -i -- "$JAR_LIST" || return $?;;
      *.sh ) vdo bash -- "$ITEM" "$JAR_LIST" || return $?;;
      * ) echo "E: unsupported filename extension: $ITEM" >&2; return 3;;
    esac
  done
  ITEM="$(grep -Pe '^\w' -- "$JAR_LIST")"
  case "$ITEM" in
    '' ) echo 'E: No JAR remaining after filtering.' >&2; return 4;;
    *$'\n'* )
      echo "E: Too many JARs remaining after filtering: ${ITEM//$'\n'/¶ }" >&2
      return 4;;
  esac
  ITEM="$JAR_DIR/$ITEM"
  echo "orig_jar_path=$ITEM" >&6

  ( echo
    echo '```text'
    echo "Original JAR:  $ITEM"
    echo "Artifact name: ${VARI[artifact]}"
    echo '```'
    echo
  ) >&7

  local RLS_DIR='release'
  mkdir --parents -- "$RLS_DIR" || return $?
  local RLS_JAR="$RLS_DIR/${VARI[artifact]}"
  mv --verbose --no-target-directory -- "$ITEM" "$RLS_JAR" || return $?
  vdo nice_ls -- "$RLS_DIR"/ || return $?

  unzip -d "$JAR_UNP" -- "$RLS_JAR" || return $?
  ITEM='tmp.files_in_jar.txt'
  VDO_TEE="$ITEM" vdo find_vsort "$JAR_UNP" || return $?
  ghstep_dump_file 'Files in the JAR' text "$ITEM" || return $?
}


function build_jar_add_extra_files () {
  local SRC_DIR="$1"
  local LIST=()
  readarray -t LIST < <(unindent_unblank <<<"${JOB[jar_add_${SRC_DIR}_files]}
      " | sed -re 's!\s+(->)\s+! \1 !g')
  local SRC_FILE= DEST_FILE=
  for SRC_FILE in "${LIST[@]}"; do
    DEST_FILE="$JAR_UNP/${SRC_FILE##* -> }"
    SRC_FILE="$SRC_DIR/${SRC_FILE% -> *}"
    mkdir --parents -- "$(dirname -- "$DEST_FILE")"
    cp --verbose --no-target-directory -- "$SRC_FILE" "$DEST_FILE" || return $?
  done
}


function build_grab_found_no_jars () {
  echo 'E: Found no JAR candidates.' >&2
  echo
  echo 'H: Check the list "Newly created lentic files"' \
    'in the summary for ideas where the JARs might be.'
  local MAYBE=
  if [ ! -d "$JAR_DIR" ]; then
    echo 'W: JAR dir "'"$JAR_DIR"'" does not seem to be a directory!' >&2
    MAYBE="$(find lentic/ -maxdepth 4 -type d -name build)"
    [ -z "$MAYBE" ] || echo "H: Might it be one of these? ${MAYBE//$'\n'/ | }"
  fi
}


function build_guess_minecraft_version () {
  local VER="${VARI[grpr_minecraft_version]}"
  if [ -n "$VER" ]; then echo "$VER"; return 0; fi

  sed -nre 's~\s+|"~~g;s~^minecraftVersion=~~p' \
    -- lentic/gradle/libs.versions.toml 2>/dev/null | grep . && return 0
}








build_init "$@"; exit $?
