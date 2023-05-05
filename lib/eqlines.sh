#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function eqlines_read_dict () {
  local DICT="$1"; shift
  local PREFIX="$1"; shift
  local KEY= VAL=
  while IFS= read -r KEY; do
    IFS= read -r VAL
    eval "$DICT"'["$PREFIX$KEY"]="$VAL"'
  done < <(sed -nre 's~\s*=\s*~\n~p')
}


function eqlines_dump_dict () {
  local DICT="$1"; shift
  local KEYS=()
  readarray -t KEYS < <( eval 'printf -- "%s\n" "${!'"$DICT"'[@]}"' \
    | sort --version-sort )
  local KEY= VAL=
  for KEY in "${KEYS[@]}"; do
    eval 'VAL="${'"$DICT"'[$KEY]}"'
    case "$VAL" in
      *$'\n'* )
        echo "E: Multi-line value currently not supported in dict $DICT" \
          "key «$KEY» = «$VAL»" >&2
        return 3;;
    esac
    KEY="${KEY#$EQLN_STRIP_KEY_PREFIX}"
    KEY="${KEY%$EQLN_STRIP_KEY_SUFFIX}"
    echo "$EQLN_ADD_KEY_PREFIX$KEY$EQLN_ADD_KEY_SUFFIX${EQLN_EQ:-=}$VAL"
  done
}











[ "$1" == --lib ] && return 0; "$@"; exit $?
