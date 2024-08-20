#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function build_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH" || return $?
  if [ "$1" == --bypass-mutex ]; then shift; "$@"; return $?; fi

  if [ -n "$GRADLE_BUILD_HELPER_MAIN_PID" ]; then
    echo E: "GRADLE_BUILD_HELPER_MAIN_PID = '$GRADLE_BUILD_HELPER_MAIN_PID'" >&2
    export GRADLE_BUILD_HELPER_MAIN_PID=$BASHPID
  fi
  local BUILD_ERR_LOG="tmp.build_step_errors.log"
  # mv --verbose --no-target-directory -- "$BUILD_ERR_LOG" \
  #   "tmp.bak-$EPOCHSECONDS-$$.${BUILD_ERR_LOG#tmp.}"
  >"$BUILD_ERR_LOG" || return $?$(
    echo E: "Failed to create build error log file: $BUILD_ERR_LOG" >&2)
  exec 2> >(exec tee -- "$BUILD_ERR_LOG" >&2)

  source -- lib/eqlines.sh --lib || return $?
  source -- lib/kisi.sh --lib || return $?

  [ -n "$GITHUB_OUTPUT" ] || local GITHUB_OUTPUT='tmp.ghout.txt'
  [ -n "$GITHUB_STEP_SUMMARY" ] || local GITHUB_STEP_SUMMARY='tmp.ghsum.txt'
  [ "$USER" == runner ] || >"$GITHUB_STEP_SUMMARY" >"$GITHUB_OUTPUT"
  exec </dev/null
  exec 6>>"$GITHUB_OUTPUT" || return $?
  exec 7>>"$GITHUB_STEP_SUMMARY" || return $?

  [ -n "$JOB_SPEC_DIR" ] || export JOB_SPEC_DIR='tmp.job'
  local -A MEM=()
  local -A JOB=(
    [max_concurrency]=64
    [grab_ls_before_jar]=". $JOB_SPEC_DIR/ lentic/"
    [lentic_jar_dir]='build/libs'
    [github_jobmgmt_dura_sec]=30  # for setting up the job, cleanup tasks etc.
    [total_dura_tolerance_sec]=30 # tolerance for e.g. rounding errors.
    [hotfix_timeout]='30s'
    [release_dir]='release'
    )
  [ -d "$JOB_SPEC_DIR" ] || ln --symbolic --no-target-directory \
    -- ../job "$JOB_SPEC_DIR" || return $?
  source -- "$JOB_SPEC_DIR"/job.rc || return $?$(
    echo "E: Failed to read job description." >&2)

  local -A VARI=()
  [ ! -f tmp.variation.dict ] || eval "VARI=(
    $(cat -- tmp.variation.dict) )" || return $?
  # local -p

  local TASK="$1"; shift
  build_"$TASK" "$@"
  local RV=$?
  [ "$RV" == 0 ] && return 0

  ghstep_dump_file 'Build step error log' text "$BUILD_ERR_LOG" || return $?
  [ -z "$CI" ] || echo :
  echo "E: Build task $TASK failed, rv=$RV"

  # On GitHub, print 15 colon lines to make a visible big gap in the raw log:
  [ -z "$CI" ] || printf '%15s' '' | sed -re 's~ ~:\n~g'

  [ "$RV" == 0 ] || github_ci_workaround_fake_success_until_date || return "$RV"
}


function build_git_basecfg () {
  [ "$USER" == runner ] || return 0
  local C='git config --global'
  $C user.name 'CI'
  $C user.email 'ci@example.net'
  $C init.defaultBranch default_branch
}


function build_clone_lentic_repo () {
  local CLONE_CMD=(
    git
    clone
    --single-branch
    --branch="${JOB[lentic_ref]}"
    -- "${JOB[lentic_url]}"
    lentic
    )
  printf -- '`%s` &rarr; `%s`\n\n' "${FUNCNAME#*_}" "${CLONE_CMD[*]}" \
    >&7 || return $?

  if [ -f lentic/.git/config ]; then
    echo 'Skip cloning: Repo lentic already exists.'
  else
    vdo "${CLONE_CMD[@]}" || return $?
  fi

  local V="${JOB[lentic_rebranch]}"
  if [ -z "$V" ]; then
    true
  elif [ "$V" == "$(git_in_lentic branch --show-current)" ]; then
    echo "D: Lentic repo's branch already is '$V'."
  else
    vdo git_in_lentic checkout -b "$V" || return $?
  fi

  V="${JOB[lentic_reset]}"
  [ -z "$V" ] || vdo git_in_lentic reset --hard "$V" || return $?
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
  K="$JOB_SPEC_DIR/$V"
  [ ! -s "$K" ] || cat -- "$K" >"tmp.$V" || return $?
  V="tmp.$V"
  V="$( [ -s "$V" ] && grep -Pe '\S' -- "$V" )"
  [ -n "$V" ] || V='""'
  local N_VARI="${V//[^$'\n']/}"
  let N_VARI="${#N_VARI}+1"
  V="[ ${V//$'\n'/, } ]"
  echo "vari=$V" >&6 || return $?
  build_predict_eta >&6 || return $?

  nl -ba -- "$GITHUB_OUTPUT" || return $?
  echo "Building $N_VARI variation(s)." \
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
  VARI[java_ver]="${JOB[java_ver]:-21}"

  eqlines_dump_dict VARI >&6 || return $?
  local REBASH="$(dump_bash_dict_pairs VARI)"
  [ -n "$REBASH" ] || return 4$(echo 'E: VARI dict dump is empty!' >&2)
  echo "$REBASH" >tmp.variation.dict || return $?
  echo "bash_dict_pairs=$REBASH" >&6 || return $?
  nl -ba -- "$GITHUB_OUTPUT" || return $?
}


function git_in_lentic () {
  GIT_DIR=lentic/.git/ GIT_WORK_TREE=lentic/ git "$@"
}


function build_run_patcher () {
  local FIX="$1"; shift
  local OPT=
  case "$FIX" in
    *.sed ) OPT='-i';;
  esac
  local WRAPS=(
    vdo
    timeout ${JOB[hotfix_timeout]}
    )
  if [ -x "$FIX" ]; then
    "${WRAPS[@]}" ./"$FIX" $OPT -- "$@"
    return $?
  fi
  case "$FIX" in
    *.sed ) "${WRAPS[@]}" sed -rf "$FIX" -$OPT -- "$@" || return $?;;
    *.sh ) "${WRAPS[@]}" bash -- "$FIX" "$@" || return $?;;
    * ) echo "E: unsupported filename extension: $FIX" >&2; return 3;;
  esac
}


function build_apply_hotfixes () {
  vdo git_in_lentic log --oneline -n 20 \
    | ghstep_dump_file 'git history before hotfixes' text || return $?
  build_apply_hotfixes__phase early || return $?
  build_apply_hotfixes__phase fix || return $?
  build_apply_hotfixes__phase late || return $?

  local MODIF='tmp.hotfix.modif_files.txt'
  VDO_TEE="$MODIF" vdo git_in_lentic status --short
  ghstep_dump_file 'Hotfixed files' text "$MODIF" || return $?

  if [ ! -s "$MODIF" ]; then
    echo "D: Hotfixes caused no changes in git-tracked files."
    return 0
  fi

  git_in_lentic commit -m 'Apply hotfixes' || return $?
  git_in_lentic format-patch --irreversible-delete --stdout 'HEAD~1..HEAD' \
    | ghstep_dump_file 'Hotfix patch' diff || return $?
}


function build_apply_hotfixes__phase () {
  local PHASE="$1"
  local FIX=
  [ -z "$PHASE" ] || FIX=".$PHASE"
  local SCAN=(
    find
    "$JOB_SPEC_DIR"/hotfixes/
    -type f
    '(' -false
      -o -name "*$FIX.sed"
      -o -name "*$FIX.sh"
      ')'
    -printf '%f\t%p\n'
    )
  readarray -t SCAN < <("${SCAN[@]}" | sort --version-sort | cut -sf 2-)

  for FIX in "${SCAN[@]}"; do
    build_apply_hotfixes__one_patch "$FIX" || return $?
  done
}


function build_apply_hotfixes__one_patch () {
  local FIX="$1"
  echo "D: Patch: $FIX"

  if git_in_lentic status --short | grep -Pe '^.\S'; then
    echo 'E: Flinching: Found unstaged changes before patch!' >&2
    return 4
  fi

  local ORIG="${FIX%.*.*}"
  ORIG="lentic/${ORIG#*/*/}"
  build_run_patcher "$FIX" "$ORIG" || return $?

  if git_in_lentic status --short | grep -Pe '^.\S'; then
    vdo git_in_lentic add -A . || return $?
    return 0
  fi

  if grep -Pe '^## '-- "$FIX" | grep -qwFe 'optional_patch'; then
    echo "D: Optional patch caused no unstaged changes."
    return 0
  fi

  echo "E: No unstaged changes after patch" \
    "and patch is not marked as optional." >&2
  git_in_lentic status --short | base64
  return 8
}


function build_detect_lentic_meta () {
  local PROP="$1"
  local VAL=
  local SIMP=()
  case "$PROP" in
    project_version ) SIMP=(
      '!mod_version=' lentic/gradle.properties
      '!version=' lentic/gradle.properties
      '!base_version=' lentic/gradle.properties
      );;
    project_name ) SIMP=(
      '!rootProject\.name=' lentic/settings.gradle{,.*,.kts}
      '!mod_id=' lentic/gradle.properties
      '!archives_base_name=' lentic/gradle.properties
      );;
    minecraft_version ) SIMP=(
      '!minecraft_version=' lentic/gradle.properties
      '!minecraftVersion=' lentic/gradle/libs.versions.toml
      '!valminecraftVersion=' lentic/{*-,}fabric/build.gradle.kts
      );;
    * )
      echo "E: $FUNCNAME: Unsupported meta prop: '$PROP'" >&2
      return 3;;
  esac
  [ -z "${SIMP[0]}" ] || VAL="$(
    build_detect_lentic_meta__simple "${SIMP[@]}")"

  VAL="${VAL//$'\r'/}"  # <- in case we forgot in a detector
  VAL="$(<<<"$VAL" sort --unique)"
  local BEFORE=
  until [ "$VAL" == "$BEFORE" ]; do
    BEFORE="$VAL"
    VAL="${VAL%[/_.-]}"
  done
  case "$VAL" in
    '' ) echo "E: $FUNCNAME '$PROP': Found nothing" >&2; return 4;;
    *$'\n'* )
      echo "E: $FUNCNAME '$PROP': Found too many candidates:" \
        "${VAL//$'\n'/¶ }" >&2
      return 4;;
  esac
  echo "$VAL"
}


function build_detect_lentic_meta__simple () {
  local BASE_SED='s~\s+|\x22|\x27~~g'  # <-- \s especially because of \r$
  local FILE= RX=
  for FILE in "$@"; do
    if [ "${FILE:0:1}" == '!' ]; then
      RX="$BASE_SED;s!^${FILE:1}!!p"
      continue
    fi
    [ -n "$RX" ] || return 3$(
      echo "E: $FUNCNAME: No regexp for file '$FILE'" >&2)
    sed -nrf <(echo "$RX") -- "$FILE" 2>/dev/null
  done
}


function build_gen_artifact_name () {
  local ARTI="${JOB[artifact]}"
  case "$ARTI" in
    '' ) ;; # guess.
    *'<'*'>'* )
      echo 'E: Slot names in artifact name are not supported yet.' >&4
      return 3;;
    * ) echo "$ARTI"; return 0;;
  esac

  local PROJ_NAME="$(build_detect_lentic_meta project_name)"
  [ -n "$PROJ_NAME" ] || PROJ_NAME='unnamed_project'
  local PROJ_VER="$(build_detect_lentic_meta project_version)"
  ARTI="$PROJ_NAME-v$PROJ_VER"

  local MC_VER=
  MC_VER="$(build_detect_lentic_meta minecraft_version)" || return $?
  [ -n "$MC_VER" ] && case "$PROJ_VER" in
    *-[Mm][Cc]"$MC_VER" | \
    *-[Mm][Cc]"$MC_VER".0 | \
    *-"$MC_VER".0 | \
    *-"$MC_VER" ) MC_VER=;;
  esac
  [ -z "$MC_VER" ] || ARTI+="$(version_triad_if_set "$MC_VER" -mc)"

  local -p >&2
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
  local ARTIFACT="$(build_gen_artifact_name)"
  [ -n "$ARTIFACT" ] || return 4$(echo 'E: Failed to decide artifact name!' >&2)
  echo "artifact=$ARTIFACT" >&6

  cd -- lentic || return $?
  local GW_OPT=(
    --stacktrace
    --info
    --scan
    )

  # Chmod only after hotfixes, becuase hotfixes expect the repo to be clean.
  chmod a+x -- gradlew || return $?
  # ^-- Some repos don't have +x. Maybe their maintainers use Windows.

  vdo ./gradlew clean "${GW_OPT[@]}" || true
  vdo rm -r -- .gradle .idea build || true
  local GR_LOG='../tmp.gradlew.log'
  VDO_TEE="$GR_LOG" vdo ./gradlew build "${GW_OPT[@]}" && return 0
  local GR_RV=$?

  local GR_HL='../tmp.gradlew.hl.log'
  "$SELFPATH"/lib/gradle_log_highlights.sed "$GR_LOG" | tee -- "$GR_HL"
  fmt_markdown_details_file "Gradle failed, rv=$GR_RV" text "$GR_HL" >&7

  return "$GR_RV"
}


function build_grab () {
  [ -n "$ARTIFACT" ] || return 4$(echo 'E: Empty artifact name!' >&2)

  local NLF='tmp.new_lentic_files.txt'
  find_vsort lentic/ -mindepth 1 -type d -name '.*' -prune , \
    -newer tmp.variation.dict -print | cut -d / -sf 2- >"$NLF" || return $?
  ghstep_dump_file 'Newly created lentic files' text "$NLF" || return $?

  local JAR_UNP='jar-unpacked'
  mkdir --parents -- "$JAR_UNP"
  vdo nice_ls -- ${JOB[grab_ls_before_jar]} || true
  vdo build_jar_add_extra_files lentic || return $?
  vdo build_jar_add_extra_files "$JOB_SPEC_DIR" || return $?

  local ORIG_JAR=
  build_grab_guess_jar_file "ORIG_JAR='¤'" || return $?
  [ -n "$ORIG_JAR" ] || return $?$(echo "E: Failed to guess JAR file." >&2)
  [ -f "$ORIG_JAR" ] || return $?$(
    echo "E: Guessed JAR file is not a regular file: '$ORIG_JAR'" >&2)
  echo "orig_jar_path=$ORIG_JAR" >&6

  ( echo
    echo '```text'
    echo "Original JAR:  $ORIG_JAR"
    echo "Artifact name: $ARTIFACT"
    echo '```'
    echo
  ) >&7

  mkdir --parents -- "${JOB[release_dir]}" || return $?
  local RLS_JAR="${JOB[release_dir]}/$ARTIFACT"
  mv --verbose --no-target-directory -- "$ORIG_JAR" "$RLS_JAR" || return $?
  vdo nice_ls -- "${JOB[release_dir]}"/ || return $?

  unzip -d "$JAR_UNP" -- "$RLS_JAR" || return $?
  local VDO_TEE='tmp.files_in_jar.txt'
  vdo find_vsort "$JAR_UNP" || return $?
  ghstep_dump_file 'Files in the JAR' text "$VDO_TEE" || return $?
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


function build_grab_guess_jar_file () {
  local REPORT="${1:-echo '¤'}"; shift
  local JAR_DIR="lentic/${JOB[lentic_jar_dir]}"
  local JAR_LIST='tmp.jars.txt'
  find_vsort "$JAR_DIR" -maxdepth 1 -type f -name '*.jar' \
    -printf '%f\n' >"$JAR_LIST" || true
  vdo base64 --wrap=512 -- "$JAR_LIST"
  ghstep_dump_file 'JARs found before filtering' text "$JAR_LIST" || return $?
  if [ ! -s "$JAR_LIST" ]; then
    build_grab_found_no_jars
    return 4
  fi

  local ITEM= OPT=
  for ITEM in "$JOB_SPEC_DIR"/jar_filter{/[0-9]*,}.{sed,sh}; do
    [ -f "$ITEM" ] || continue
    build_run_patcher "$ITEM" "$JAR_LIST" || return $?
  done

  ITEM="$(grep -Pe '^\w' -- "$JAR_LIST")"
  case "$ITEM" in
    '' ) echo 'E: No JAR remaining after custom filters.' >&2; return 4;;
    *$'\n'* ) ;;
    * ) build_grab_guess_jar_file__report; return $?;;
  esac

  echo 'W: Too many JARs remaining after custom filters:' >&2
  nl -ba <<<"$ITEM" >&2
  echo 'D: Retrying with additional default filters.'
  local DFF='
    /\-(debug|sources)?\.jar$/d
    '
  ITEM="$(<<<"$ITEM" sed -rf <(echo "$DFF") )"

  case "$ITEM" in
    '' ) echo 'E: No JAR remaining after default filters.' >&2; return 4;;
    *$'\n'* )
      echo 'E: Too many JARs remaining after default filters:' >&2
      nl -ba <<<"$ITEM" >&2
      return 4;;
  esac

  build_grab_guess_jar_file__report; return $?
}


function build_grab_guess_jar_file__report () {
  echo "D: $FUNCNAME: >> $REPORT <<" >&2
  REPORT="${REPORT//¤/"$JAR_DIR/$ITEM"}"
  eval "$REPORT"
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


function github_ci_workaround_fake_success_until_date () {
  local D="${JOB[$FUNCNAME]}" J= UTS= W=
  if [ -z "$D" ]; then
    W='If this failure is too noisy, consider the ¹ option.'
  else
    UTS="$(date +%s --date="$D")"
    [ "${UTS:-0}" -ge 1 ] || W='Failed to parse the date for ¹.'
    if [ -z "$W" -a "$UTS" -lt "$EPOCHSECONDS" ]; then
      W='The date for ¹ has expired.'
      D=
    fi
  fi
  if [ -n "$D" ]; then
    D="lentic/${JOB[lentic_jar_dir]}"
    mkdir --parents -- "$D"
    J="$FUNCNAME.jar"
    echo "artifact=$J" >&6
    J="$D/$J"
    D+="/$FUNCNAME.txt"
    if [ -f "$J" ]; then
      [ -n "$W" ] || W="Decoy file already exists: \`$J\`"
    else
      [ -n "$W" ] || W="Creating decoy file: \`$J\`"
      echo "JOB[$FUNCNAME]='$YMD'" >"$D" || return $?$(
        echo "E: Failed to create file: $D"$'\n' >&7)
      zip -j0o "$J" -- "$D" || return $?$(
        echo "E: Failed to JAR-pack file: $J"$'\n' >&7)
    fi
  fi
  W="${W//¹/\`$FUNCNAME\`}"
  W="## ⚠️ ⚠️ W: $W ⚠️ ⚠️"
  echo $'\n'"$W"$'\n' >&7
  [ -n "$D" ] || return 4
}













build_init "$@"; exit $?
