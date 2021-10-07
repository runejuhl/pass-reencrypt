#!/bin/bash

declare -x \
        PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-${HOME}/.password-store}" \
        PASSWORD_STORE_GPG_OPTS=${PASSWORD_STORE_GPG_OPTS:-} \
        PASSWORD_STORE_KEY=${PASSWORD_STORE_KEY:-} \
        PASSWORD_STORE_SIGNING_KEY=${PASSWORD_STORE_SIGNING_KEY:-} \
        INNER_GIT_DIR=${INNER_GIT_DIR:-} \
        gpgid=

# source the functions from pass
# shellcheck disable=SC1090
source <(grep -B99999 'END subcommand functions' "$(command -v pass)")

set -euo pipefail

function reencrypt_file() {
  declare passfile="${1}" \
          gpg_keys="$2"

  local passfile_temp="${passfile}.tmp.${RANDOM}.${RANDOM}.${RANDOM}.${RANDOM}.--"

  current_keys="$(LC_ALL=C $GPG "$PASSWORD_STORE_GPG_OPTS" -v --no-secmem-warning --no-permission-warning --decrypt --list-only --keyid-format long "$passfile" 2>&1 | sed -n 's/^gpg: public key is \([A-F0-9]\+\)$/\1/p' | LC_ALL=C sort -u)"

  if [[ $gpg_keys != "$current_keys" ]]; then
    echo "${passfile#$PREFIX/}: reencrypting to '${gpg_keys}'"
    (
      $GPG -d "${GPG_OPTS[@]}" "$passfile" | \
        $GPG -e "${GPG_RECIPIENT_ARGS[@]}" -o "$passfile_temp" "${GPG_OPTS[@]}" && \
        mv "$passfile_temp" "$passfile"
    ) || rm -f "$passfile_temp"
  fi

}

for path in "${@}"; do
  passname="$PREFIX/$path"
  passfile="${passname}.gpg"
  d="$(dirname "$passfile")"

  while [[ "$d" != "$(dirname "$PREFIX")" && "$d" != '/' ]]; do
    gpg_id_file="$(find -L "$d" -maxdepth 1 -name '.gpg-id' -print -quit)"
    if [[ -n "$gpg_id_file" ]]; then
      break
    fi

    d="$(dirname "$d")"
  done

  if [[ "$(basename "$gpg_id_file")" != '.gpg-id' ]]; then
     2< echo "Failed to find .gpg-id file; aborting"
     exit 1
  fi

  set_git "$gpg_id_file"
  set_gpg_recipients "$passfile"
  gpg_ids=''
  GPG_RECIPIENTS=( )
  GPG_RECIPIENT_ARGS=( )

  while read -r gpg_id; do
    GPG_RECIPIENT_ARGS+=( "-r" "$gpg_id" )
    GPG_RECIPIENTS+=( "$gpg_id" )
    gpg_ids+=" ${gpg_id}"
  done < "$gpg_id_file"

  reencrypt_file "$passfile" "$gpg_ids"
  git_add_file "$passfile" "Reencrypt '${passname}' using GPG IDs '${gpg_ids}'."
done
