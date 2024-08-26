#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function create_build_branch () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local REPO_DIR="$(readlink -m -- "$BASH_SOURCE"/../..)"

  local -A MEM=() JOB=()
  MEM[worktree_subdir_prefix]='W.'
  MEM[license_hashes_cache]='tmp.licenses.sha'

  local CLUE=
  for CLUE in "$@"; do
    interpret_clue || return 0
  done

  if [ "$#" == 0 -a -f job.rc ]; then
    source -- job.rc || return 4$(
      echo E: "Failed to source assumed-existing job.rc!" >&2)
    new_worktree_welcome
    return $?
  fi

  [ -n "${MEM[branch]}" ] || return 4$(
    echo "E: Failed to guess a branch name from the clues given." >&2)
  [ -n "${JOB[lentic_url]}" ] || return 4$(
    echo "E: Failed to guess the lentic_url." >&2)
  cd -- "$REPO_DIR" || return $?
  check_repo_clean || return $?

  local WTSUF="${MEM[worktree_subdir_prefix]}"
  local WTREE="${MEM[worktree_subdir]}"
  [ -n "$WTREE" ] || WTREE="$WTSUF${MEM[gh_repo]}"
  actually_create_worktree || return $?
  cd -- "$REPO_DIR/$WTREE" || return $?$(
    echo E: "Failed to chdir into the assumed-existing worktree: $WTREE" >&2)
  new_worktree_welcome || return $?
  echo "# Success! To work further: cd $WTREE"
  echo "# to rename it: git worktree move $WTREE ${WTSUF}some-other-name"
}


function new_worktree_welcome () {
  download_potential_license_files || return $?
  adjust_licenses_in_jobrc || return $?
  git add job.rc || return $?
  git diff HEAD || return $?
}


function actually_create_worktree () {
  git worktree add "$WTREE" || return $?$(
    echo E: "Failed to create the worktree: $WTREE" >&2)
  cd -- "$REPO_DIR/$WTREE" || return $?$(
    echo E: "Failed to chdir into the new worktree: $WTREE" >&2)
  git branch -m "$WTREE" "${MEM[branch]}" || return $?$(
    echo E: "Failed to rename the worktree branch!" >&2)
  git reset --hard base-for-build-branches || return $?
  generate_default_jobrc >job.rc || return $?
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
  interpret_clue__worktree_subdir "$CLUE" && return 0
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


function interpret_clue__worktree_subdir () {
  local WT="$1"
  [[ "$WT" == "${MEM[worktree_subdir_prefix]}"* ]] || return 1
  WT="${WT%/}"
  case "$WT" in
    *[^A-Za-z0-9-.]* ) return 1
  esac
  MEM[worktree_subdir]="$WT"
}


function generate_default_jobrc () {
  echo '# -*- coding: utf-8, tab-width: 2 -*-'
  echo
  dfjobval estimated_build_duration_per_variation '7–10 minutes'
  dfjobval max_build_duration_sec_per_variation '$(( 10 * 60 ))'
  dfjobval github_ci_workaround_fake_success_until_date '1970-01-01'
  dfjobval lentic_url
  dfjobval lentic_ref
  dfjobval lentic_license_sha1s '0000…0000 *LICENSE'
  dfjobval jar_add_lentic_files 'LICENSE -> LICENSE.txt'
  <<<"${JOB[+]}" sed -nre 's~$~\x27~;s~^(\S+)\s+~JOB[\1]=\x27~p'
}


function download_lentic_file () {
  local SUB_FILE="$1"; shift
  local URL="${JOB[lentic_url]%.git}/raw/${JOB[lentic_ref]}/$SUB_FILE"
  local SAVE_AS="${SUB_FILE##*/}"
  cache-file-wget "$SAVE_AS" "$@" "$URL" || return $?
}


function download_potential_license_files () {
  local CACHE="${MEM[license_hashes_cache]}"
  if [ -s "$CACHE" ]; then
    echo D: $FUNCNAME: "Skip: License checksum cache file is not empty: $CACHE"
    return 0
  fi
  local BFNS=(
    License
    Copying
    )
  local FEXTS=(
    ''
    .txt
    .md
    )
  local BFN= FEXT= SRC=
  local FOUND=()
  echo -n "Trying to auto-detect the license file(s): "
  for BFN in "${BFNS[@]}"; do
    for BFN in "${BFN^^}" "$BFN" "${BFN,,}"; do
      for FEXT in "${FEXTS[@]}"; do
        SRC="$BFN$FEXT"
        echo -n "'$SRC'?"
        if download_lentic_file "$SRC" --quiet; then
          echo -ne '\b\e[97;42m√\e[0m'
          FOUND+=( "$SRC" )
        else
          echo -ne '\b\e[97;41m×\e[0m'
          rm -- tmp.*."$SRC".part 2>/dev/null
        fi
        echo -n ' '
      done
    done
  done
  local N_FOUND="${#FOUND[@]}"
  echo "Found $N_FOUND license files."
  [ "$N_FOUND" -ge 1 ] || return 0
  sha1sum --binary -- "${FOUND[@]}" >"$CACHE"
  git add -- "${FOUND[@]}"
  local MSG='Add license file'
  [ "$N_FOUND" -lt 2 ] || MSG+='s'
  git commit -m "$MSG" -- "${FOUND[@]}"
}


function adjust_licenses_in_jobrc () {
  local CACHE="${MEM[license_hashes_cache]}"
  local FIRST_LICENSE_FILE="$(sed -nre 's~^\S+ *\*?~~p;q' -- "$CACHE")"
  [ -n "$FIRST_LICENSE_FILE" ] || return 4$(
    echo E: $FUNCNAME: 'Cannot determine first license file!' >&2)
  sed -zrf <(echo '
    s~\r|\f~~g
    s~(^|\n)(JOB\[jar_add_lentic_files\]=\x27|$\
      )(\S+ -> |)(LICENSE\.)~\1\2\f<jarlic>\n\r -> \4~g
    s~(^|\n)(JOB\[lentic_license_sha1s\]=\x27|$\
      )[^\x27]*(\x27)~\1\2\f<shas>\n\r\3~g
    ') -- job.rc | sed -re '/\f<shas>$/r /dev/fd/5' 5< <(sed -rf <(echo '
      1{$!s~^~\n  ~}
      2,${s~^~  ~;$s~$~\n  ~}
      ') -- "$CACHE"
    ) | sed -re '/\f<jarlic>$/a\'"$FIRST_LICENSE_FILE" \
    | sed -zre 's~\f\S+\n~~g;s~\n\r~~g' >tmp.new.job.rc || return $?
  [ -s tmp.new.job.rc ] || return $?$(echo E: $FUNCNAME: >&2 \
    'Updated job.rc would be empty!' >&2)
  mv --no-target-directory -- {tmp.new.,}job.rc || return $?
}












create_build_branch "$@"; exit $?
